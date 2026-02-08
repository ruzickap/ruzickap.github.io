---
title: Encrypted disks with remote key placed on http server
author: Petr Ruzicka
date: 2009-06-07
description: Set up LUKS-encrypted disks using dm-crypt with GPG-encrypted keys fetched from a remote HTTP server
categories: [Linux, Storage, Security, linux-old.xvx.cz]
tags: [lvm, bash, security]
---

> <https://linux-old.xvx.cz/2009/06/crypted-disks-with-remote-key-placed-on-http-server/>
{: .prompt-info }

This page contains some information on how to create an encrypted disk using
dm_crypt, lvm, gpg with a remote key stored on an HTTP server.
The advantage is to have the key, used for unlocking encrypted disk(s),
somewhere on the server instead of having it on USB.

* You can easily delete this key if your disks are stolen and nobody can
  access them any longer...
* If you use a USB stick to save the key then you need to have it connected to
  the machine with the encrypted disks every reboot - usually it will be
  plugged all the time to the server which destroys all security.
* Keys are downloaded automatically every reboot from remote HTTP server
  (if not your disks will remain locked)

All commands were tested on Debian and should be also applicable on other
distributions.

## Remote server side

Generate a new key pair:

```bash
gpg --gen-key
```

List the keys and write down the secret key ID `9BB7698A`:

```console
gpg --list-keys

/root/.gnupg/pubring.gpg
------------------------
pub   1024D/9BB7698A 2009-06-07
uid                  test_name (test_comment) test@xvx.cz
sub   2048g/A0DA1037 2009-06-07
```

Export the private key and save it somewhere "public" temporarily...

```bash
gpg --verbose --export-options export-attributes,export-sensitive-revkeys --export-secret-keys 9BB7698A > ~/public_html/secret.key
```

Generate a random key and encrypt it with the previously generated private key.
That will be the key used for dm-crypt:

```bash
head -c 256 /dev/urandom | gpg --batch --passphrase test --verbose --throw-keyids --local-user 9BB7698A --sign --yes --cipher-algo AES256 --encrypt --hidden-recipient 9BB7698A --no-encrypt-to --output ~/public_html/abcd.html -
```

## Client side (where the data will be encrypted)

Log in to the machine where you want to encrypt your data.

Create an LVM volume:

```bash
#lvremove -f lvdata
#vgremove -f vgdata
pvcreate -ff -v /dev/hda2 /dev/hdb1
vgcreate -v -s 16 vgdata /dev/hda2 /dev/hdb1
lvcreate -v -l 100%FREE vgdata -n lvdata
```

Import the secret private key from the HTTP server (don't forget to remove
`secret.key` from the server after this) and then download and decrypt the
cipher key for dm-crypt `/mykey`:

```bash
#gpg --yes --delete-secret-keys 9BB7698A
#gpg --yes --batch --delete-keys 9BB7698A
wget https://10.0.2.2/~ruzickap/secret.key -O - | gpg --import -
wget https://10.0.2.2/~ruzickap/abcd.html -O - | gpg --quiet --passphrase test --batch --decrypt > /mykey
```

Encrypt the lvm `vgdata-lvdata` using `/mykey`:

```bash
cryptsetup -s 512 -c aes-xts-plain luksFormat /dev/mapper/vgdata-lvdata /mykey
```

Add the dm-crypt key `/mykey` to the "LUKS":

```bash
cryptsetup --key-file=/mykey luksOpen /dev/mapper/vgdata-lvdata vgdata-lvdata_crypt
```

Format opened LUKS and copy there some data:

```bash
mkfs.ext3 /dev/mapper/vgdata-lvdata_crypt
mount /dev/mapper/vgdata-lvdata_crypt /mnt
cp /etc/* /mnt/
umount /mnt
cryptsetup luksClose vgdata-lvdata_crypt
rm /mykey
```

Now we have to create a short script `/script` that will download the key from
the remote server and decrypt it using the imported secret key with GPG and
display it on the screen:

```bash
#!/bin/bash
/usr/bin/wget --quiet https://10.0.2.2/~ruzickap/abcd.html -O - | /usr/bin/gpg --quiet --homedir /root/.gnupg --quiet --passphrase xxxx --batch --decrypt 2> /dev/null
```

We should not forget to mount our encrypted filesystem after boot
`/etc/rc.local`:

```bash
echo "Mounting encrypted file system in 5 seconds..."
sleep 5
cryptdisks_start vgdata-lvdata_crypt
mount /mnt
```

Another necessary thing needs to be done - putting the right information to
`/etc/crypttab`:

```console
vgdata-lvdata_crypt     /dev/mapper/vgdata-lvdata       none noauto,cipher=aes-xts-plain,size=512,luks,tries=1,checkargs=ext2,keyscript=/script
```

We don't want to mount the encrypted filesystem with others, because the network
is not ready at that time `/etc/fstab`:

```console
/dev/mapper/vgdata-lvdata_crypt /mnt    ext3    noauto,rw,exec,async,noatime,nocheck,data=writeback    0       0
```

This is definitely not the best way to secure your data, but it's better than
nothing.

Feel free to combine this method with keys stored on USB drive.
