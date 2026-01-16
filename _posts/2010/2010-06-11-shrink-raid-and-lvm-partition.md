---
title: Shrink RAID and LVM partition
author: Petr Ruzicka
date: 2010-06-11
categories: [Linux, Storage]
tags: [RAID, LVM, mdadm, ext4]
---

> Not completed...
{: .prompt-info }

I'm using [RAID1](https://en.wikipedia.org/wiki/RAID#RAID_1) in my servers. The
disks I used are always the same size and the same type from one company.

In one old server I had Maxtor disks, where one of the 20G disk failed. Because
it's almost impossible to buy/get another Maxtor disk of such small size I
replaced broken disk with 20G Seagate disk.

The problem began when I wanted to copy the partition layout from Maxtor to
empty Seagate and found out that Seagate is "smaller" than Maxtor.

The only way how to restore RAID1 was shrinking ext4, lvm, raid and then copy
the disk layout to smaller disk.

I have never done this before so I rather tried it in
[VirtualBox](https://en.wikipedia.org/wiki/VirtualBox) than on a live system and
wrote a few notes about it.

Let's have Debian installed on 2 10Gb disks, which using RAID1 with LVM in
VirtualBox:

```console
root@debian:~# fdisk -l /dev/sda /dev/sdb | grep 'Disk /dev/'
Disk /dev/sda: 10.7 GB, 10737418240 bytes
Disk /dev/sdb: 10.7 GB, 10737418240 bytes
```

I remove the first disk from RAID:

```console
root@debian:~# mdadm --manage /dev/md0 --fail /dev/sda1
mdadm: set /dev/sda1 faulty in /dev/md0

root@debian:~# mdadm --manage /dev/md0 --remove /dev/sda1
mdadm: hot removed /dev/sda1
```

It's time to replace first disk with smaller one in VirtualBox. Then there
should be two different disks with degraded raid array:

```console
root@debian:~# fdisk -l /dev/sda /dev/sdb | grep 'Disk /dev/'
Disk /dev/sda doesn't contain a valid partition table
Disk /dev/sda: 10.7 GB, 10704912384 bytes
Disk /dev/sdb: 10.7 GB, 10737418240 bytes

root@debian:~#  cat /proc/mdstat
Personalities : [raid1]
md0 : active raid1 sdb1[1]
      10482304 blocks [2/1] [_U]

unused devices: <none>
</none>
```

If I use sfdisk to copy partition layout from bigger disk to smaller disk I get
this warning:

```console
root@debian:~# sfdisk -d /dev/sdb | sfdisk --force /dev/sda
...
Warning: given size (20964762) exceeds max allowable size (20900502)
...
```

To prevent this error I need to shrink raid partition located on `/dev/sdb1` by
31MB.

Look at the disk layout:

```console
root@debian:~# df --total
Filesystem           1K-blocks      Used Available Use% Mounted on
/dev/mapper/VG-root     959512    148832    761940  17% /
tmpfs                   125604         0    125604   0% /lib/init/rw
udev                     10240       140     10100   2% /dev
tmpfs                   125604         0    125604   0% /dev/shm
/dev/mapper/VG-home    4559792    140136   4188028   4% /home
/dev/mapper/VG-tmp      959512     17588    893184   2% /tmp
/dev/mapper/VG-usr     1919048    262228   1559336  15% /usr
/dev/mapper/VG-var     1919048    237692   1583872  14% /var
total                 10578360    806616   9247668   9%
```

You can see there is 4G free on `/home` partition. Download and boot
[SystemRescueCD](https://www.sysresccd.org/) and shrink `ext4` first.

```console
e2fsck -f /dev/mapper/VG-home

root@sysresccd /root % resize2fs /dev/mapper/VG-home 4G
resize2fs 1.41.11 (14-Mar-2010)
Resizing the filesystem on /dev/mapper/VG-home to 1048576 (4k) blocks.
The filesystem on /dev/mapper/VG-home is now 1048576 blocks long.
```

Now the home partition has 4G and I can change size of `/dev/mapper/vg-home`.
Here is the lvm configuration:

```bash
root@sysresccd /root % lvs
  LV   VG   Attr   LSize   Origin Snap%  Move Log Copy%  Convert
  home VG   -wi-a-   4.42g
  root VG   -wi-a- 952.00m
  tmp  VG   -wi-a- 952.00m
  usr  VG   -wi-a-   1.86g
  var  VG   -wi-a-   1.86g

root@sysresccd /root % vgs
  VG   #PV #LV #SN Attr   VSize  VFree
  VG     1   5   0 wz--n- 10.00g    0

root@sysresccd /root % pvs
  PV         VG   Fmt  Attr PSize  PFree
  /dev/md0   VG   lvm2 a-   10.00g    0
```

It means:

- There are 5 logical volumes (home, root, tmp, usr, var) which belong to
  volume group "VG"
- There is volume group which occupy the whole physical volume
  (`VG 1 5 0 wz--n- 10.00g    0`)
- There is a physical volume on the whole raid
  (`/dev/md0 VG lvm2 a- 10.00g    0`)

It's necessary to reduce logical volume first:

```console
root@sysresccd /root % lvdisplay /dev/VG/home | grep 'LV Size'
  LV Size                4.42 GiB

lvreduce --size 4.1G /dev/mapper/VG-home
```

Next useful step (but not required) is extend ext4 partition to fit lvm volume:

```bash
e2fsck -f /dev/mapper/VG-home
resize2fs /dev/mapper/VG-home
```

We are done with logical volume resizing and we should see some free space in
volume group (324M):

```console
root@sysresccd / % pvs
  PV         VG   Fmt  Attr PSize  PFree
  /dev/md0   VG   lvm2 a-   10.00g 324.00m
```

Now it's necessary to shrink physical volume (the "lowest" volume) [10G -
0.031G]:

```console
pvresize /dev/md0 --setphysicalvolumesize 9.9G

root@sysresccd / % pvs
  PV         VG   Fmt  Attr PSize PFree
  /dev/md0   VG   lvm2 a-   9.90g 224.00m
```

-----------------

The last thing we need to resize is disk array:

```console
root@sysresccd / % mdadm --detail /dev/md0 | grep Size
     Array Size : 10482304 (10.00 GiB 10.73 GB)
  Used Dev Size : 10482304 (10.00 GiB 10.73 GB)

# 10433331K = 9.95 * 1024 * 1024
root@sysresccd / % mdadm --grow /dev/md0 --size=10433331
mdadm: component size of /dev/md0 has been set to 10433331K
```

Now we can safely create raid partition on the first empty "smaller" disk and
mirror data. (Use fdisk to create "Linux raid autodetect" partition [fd] on the
first disk):

```bash
mdadm --manage /dev/md0 --add /dev/sda1

mdadm --create /dev/md1 --verbose --metadata=0.90 --level=1 --raid-devices=2
/dev/sda1 missing
pvcreate /dev/md1
vgextend VG /dev/md1
pvmove /dev/md0 /dev/md1
vgreduce VG /dev/md0
pvremove /dev/md0
mdadm --stop /dev/md0
mdadm --zero-superblock /dev/sdb1
sfdisk -d /dev/sda | sfdisk --force /dev/sdb
mdadm --manage /dev/md1 --add /dev/sdb1
```
