---
title: Server RAID/BIOS changes using HP Scripting toolkit and Cobbler
author: Petr Ruzicka
date: 2013-11-27
description: Server RAID/BIOS changes using HP Scripting toolkit and Cobbler
categories: [Linux]
tags: [hp, SmartStart Scripting Toolkit, cobbler, RAID, Proliant, pxe boot, BL685c, BIOS, HP Scripting Toolkit, BL460c, nfs, dhcp]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2013/11/server-raidbios-changes-using-hp.html)
{: .prompt-info }

I have to take care of a few enclosures with HP ProLiant BL685c and HP ProLiant
BL460c blades (both G1). They are quite old now, but still can do a good job.
Because there was no operating system I had no idea how the RAID or BIOS was
configured. Obviously I want to have it configured the same and I really don't
want to go through all of them one by one and configure it manually.

Luckily for me there is an
[HP Scripting Toolkit](https://web.archive.org/web/20131201071814/http://www8.hp.com/us/en/products/server-software/product-detail.html?oid=5219389)
(or HP SmartStart Scripting Toolkit) which can boot over PXE and get/set the
BIOS/RAID configuration.
It is especially handy if you have new servers without OS installed.

Let's see how you can install and configure Cobbler, NFS, PXE, tftpboot and HP
Scripting Toolkit to modify the BIOS/RAID information on the server.

Start with installing the latest [CentOS](https://www.centos.org/), getting the
SmartStart Scripting Toolkit and basic [NFS](https://en.wikipedia.org/wiki/Network_File_System)
configuration:

```bash
yum install -y nfs-utils rpcbind

chkconfig nfs on

mkdir -p /data/hp/
chown -R nfsnobody:nfsnobody /data

cat > /etc/exports << EOF
/data                                   0.0.0.0/0.0.0.0(ro,no_root_squash,no_subtree_check,async,crossmnt,fsid=0)
/data/hp/ss-scripting-toolkit-linux     0.0.0.0/0.0.0.0(rw,no_root_squash,no_subtree_check,async,crossmnt)
EOF

wget --no-verbose http://ftp.hp.com/pub/softlib2/software1/pubsw-linux/p1221080004/v63551/ss-scripting-toolkit-linux-8.70.tar.gz -P /data/hp/

cd /data/hp/ || exit
tar xzf ss-scripting-toolkit-linux*.tar.gz
ln -s ss-scripting-toolkit-linux-8.70 ss-scripting-toolkit-linux
mkdir /data/hp/ss-scripting-toolkit-linux/blade_configs

sed -i.orig 's/export TZ=.*/export TZ=MET-1METDST/;s@export TOOLKIT_WRITE_DIR=.*@export TOOLKIT_WRITE_DIR=/data/hp/ss-scripting-toolkit-linux@;' /data/hp/ss-scripting-toolkit-linux/scripts/includes

# shellcheck disable=SC2016 # Single quotes intentional - preserving ${VARIABLE} literals in target files
sed -i.orig 's/partimage/#partimage/;s@\${PROFILE_MNT}/\${PROFILENAME}@\${PROFILE_MNT}/blade_configs/\${PROFILENAME}@;s@^\${TOOLKIT}/reboot@poweroff -f@;/Mounting Storage/a mkdir \${PROFILE_MNT}' /data/hp/ss-scripting-toolkit-linux/scripts/capture.sh /data/hp/ss-scripting-toolkit-linux/scripts/deploy.sh

# shellcheck disable=SC2016 # Single quotes intentional - preserving ${VARIABLE} literals in target files
sed -i 's@\${PROFILE_MNT}/\$PROFILENAME@\${PROFILE_MNT}/blade_configs/\$PROFILENAME@' /data/hp/ss-scripting-toolkit-linux/scripts/capture.sh

# shellcheck disable=SC2016 # Single quotes intentional - preserving ${VARIABLE} literals in target files
sed 's@/mnt/main/scripts/includes@/TOOLKIT/includes@;s@cp -a \${RAM_TOOLKIT_DIR}@#&@;s@./rbsureset -reset@./rbsureset #-reset@;s/^reboot/poweroff -f/' /data/hp/ss-scripting-toolkit-linux/contrib/LinuxCOE/scripts/systemreset.sh > /data/hp/ss-scripting-toolkit-linux/scripts/systemreset.sh
chmod a+x /data/hp/ss-scripting-toolkit-linux/scripts/systemreset.sh
```

Now install and configure [Cobbler](https://www.cobblerd.org/):

```bash
# Install EPEL
MAJOR_RELEASE=$(sed 's/.* \([0-9]*\)\.[0-9] .*/\1/' /etc/redhat-release)
cd /tmp/ || exit
lftp -e "mget /pub/linux/fedora/epel/6/x86_64/epel-release*.noarch.rpm; quit;" http://ftp.fi.muni.cz/
rpm -Uvh ./epel*"${MAJOR_RELEASE}"*.noarch.rpm

# Install Cobbler
yum install -y cobbler-web fence-agents git hardlink ipmitool dhcp

sed -i.orig 's/module = authn_denyall/module = authn_configfile/' /etc/cobbler/modules.conf
HTDIGEST_HASH=$(printf admin:Cobbler:admin123 | md5sum -)
echo "admin:Cobbler:${HTDIGEST_HASH:0:32}" >> /etc/cobbler/users.digest

PASSWORD_HASH=$(openssl passwd -1 'admin123')
sed -i.orig "s/^\(anamon_enabled:\).*/\1 1/;s@^\(default_password_crypted:\).*@\1 \"$PASSWORD_HASH\"@;s/^\(manage_dhcp:\).*/\1 1/;s/^\(next_server:\).*/\1 10.29.49.4/;s/^\(pxe_just_once:\).*/\1 1/;s/^\(server:\).*/\1 10.29.49.4/;s/^\(scm_track_enabled:\).*/\1 1/;s/^power_management_default_type:.*/power_management_default_type: 'ilo'/" /etc/cobbler/settings

# Change DHCPd template
sed -i.orig 's/192.168.1.0/10.29.49.0/;s/192.168.1.5;/10.29.49.1;/;s/192.168.1.1;/10.226.32.44;/;s/255.255.255.0/255.255.255.128/;s/192.168.1.100 192.168.1.254/10.29.49.100 10.29.49.126/;' /etc/cobbler/dhcp.template

# Change PXE template
sed -i.orig '/ONTIMEOUT/a SERIAL 0 115200' /etc/cobbler/pxe/pxedefault.template

# Configure DHCPd
sed -i.orig 's/^DHCPDARGS=.*/DHCPDARGS="eth0"/' /etc/sysconfig/dhcpd

service cobblerd restart
chkconfig cobblerd on
service httpd restart
chkconfig httpd on
chkconfig dhcpd on
service xinetd restart

# Add distro and profiles to Cobbler
cobbler distro add --name=sstk --arch=i386 --kernel=/data/hp/ss-scripting-toolkit-linux/boot_files/vmlinuz --initrd=/data/hp/ss-scripting-toolkit-linux/boot_files/initrd.img \
  --kopts '!kssendmac !ksdevice !lang !text root=/dev/ram0 rw ramdisk_size=396452 network=1 sstk_mount=10.29.49.4:/data/hp/ss-scripting-toolkit-linux sstk_mount_type=nfs sstk_mount_options=rw,nolock sstk_script=/shell.sh console=ttyS0,115200n8'

cobbler profile add --name="SSTK-Capture_and_save_system_hardware_settings" --distro=sstk --kopts="sstk_script=/capture.sh img=test_hostname" --kickstart=""
cobbler profile add --name="SSTK-Reset_system_to_factory_defaults" --distro=sstk --kopts="sstk_script=/systemreset.sh img=test_hostname" --kickstart=""
cobbler profile add --name="SSTK-Deploy_Configuration" --distro=sstk --kopts="sstk_script=/deploy.sh img=test_hostname" --kickstart=""

git config --global user.name "Config Git"
git config --global user.email root@cobbler.example.com

cobbler sync

# Just to be sure
chkconfig iptables off
service iptables stop
```

Once the tftp, NFS, dhcp is ready you can try to "Boot from Network" one of the
servers. If the networking is working fine you should at least see getting the
IP from the DHCP server and the main "blue" menu.

The full video can be seen here:

{% include embed/youtube.html id='07-0wZGKtW8' %}

You can find the examples of files modified by `sed` in the scripts in
[GitHub](https://github.com/ruzickap/linux.xvx.cz/tree/gh-pages/files/cobbler-ss_scripting_toolkit_linux).

[Example configuration files][example] - the configuration
"extracted" from the BL685c blade as shown in the video above.

[example]: https://github.com/ruzickap/linux.xvx.cz/tree/gh-pages/files/cobbler-ss_scripting_toolkit_linux/data/hp/ss-scripting-toolkit-linux/blade_configs/test_hostname/data_files

Enjoy :-)
