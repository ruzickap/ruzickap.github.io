---
title: RAID disk check in Linux
author: Petr Ruzicka
date: 2010-03-23
categories: [Linux, Storage]
tags: [RAID, SMART, mdadm, GRUB]
---

One day I checked [dmesg](https://en.wikipedia.org/wiki/Dmesg) from one of
my servers and I saw [I/O](https://en.wikipedia.org/wiki/I/O) errors :-(

```console
gate:~ dmesg
...
[ 4220.798665] ide: failed opcode was: unknown
[ 4220.798665] end_request: I/O error, dev hda, sector 21067462
[ 4222.983683] hda: dma_intr: status=0x51 { DriveReady SeekComplete Error }
[ 4222.983683] hda: dma_intr: error=0x40 { UncorrectableError }, LBAsect=21067572, sector=21067470
...
```

Lucky for me there are two disks in
[RAID 1](https://en.wikipedia.org/wiki/Raid_1#RAID_1) so my data was not lost.
The machine is "just" a firewall, so I decided to play a little bit with the
bad hard disk, because there are no important data on it. Usually if you see
errors like I mentioned above you replace disk without any questions, but I
would like to "get" some outputs from diagnostic commands. So you can see what
you can do in such case.

## S.M.A.R.T checks

The drives are pretty old, so it's better to check if they support
[S.M.A.R.T.](https://en.wikipedia.org/wiki/S.M.A.R.T.) and if it's enabled:

```console
gate:~ smartctl -i /dev/hda | grep 'SMART support'
SMART support is: Available - device has SMART capability.
SMART support is: Enabled
```

Let's check some information about the disk. You can see - it's quite old:

```console
gate:~ smartctl --attributes /dev/hda
=== START OF READ SMART DATA SECTION ===
SMART Attributes Data Structure revision number: 16
Vendor Specific SMART Attributes with Thresholds:
ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
  3 Spin_Up_Time            0x0027   235   234   063    Pre-fail  Always       -       5039
  4 Start_Stop_Count        0x0032   253   253   000    Old_age   Always       -       969
  5 Reallocated_Sector_Ct   0x0033   253   251   063    Pre-fail  Always       -       2
  6 Read_Channel_Margin     0x0001   253   253   100    Pre-fail  Offline      -       0
  7 Seek_Error_Rate         0x000a   253   252   000    Old_age   Always       -       0
  8 Seek_Time_Performance   0x0027   247   231   187    Pre-fail  Always       -       33044
  9 Power_On_Minutes        0x0032   247   247   000    Old_age   Always       -       148h+27m
 10 Spin_Retry_Count        0x002b   253   252   223    Pre-fail  Always       -       0
 11 Calibration_Retry_Count 0x002b   253   252   223    Pre-fail  Always       -       0
 12 Power_Cycle_Count       0x0032   251   251   000    Old_age   Always       -       973
192 Power-Off_Retract_Count 0x0032   253   253   000    Old_age   Always       -       842
193 Load_Cycle_Count        0x0032   253   253   000    Old_age   Always       -       3829
194 Unknown_Attribute       0x0032   253   253   000    Old_age   Always       -       0
195 Hardware_ECC_Recovered  0x000a   253   248   000    Old_age   Always       -       6580
196 Reallocated_Event_Count 0x0008   240   240   000    Old_age   Offline      -       13
197 Current_Pending_Sector  0x0008   251   247   000    Old_age   Offline      -       2
198 Offline_Uncorrectable   0x0008   253   242   000    Old_age   Offline      -       0
199 UDMA_CRC_Error_Count    0x0008   199   199   000    Old_age   Offline      -       0
200 Multi_Zone_Error_Rate   0x000a   253   252   000    Old_age   Always       -       0
201 Soft_Read_Error_Rate    0x000a   253   218   000    Old_age   Always       -       2
202 TA_Increase_Count       0x000a   253   001   000    Old_age   Always       -       0
203 Run_Out_Cancel          0x000b   253   096   180    Pre-fail  Always   In_the_past 382
204 Shock_Count_Write_Opern 0x000a   253   151   000    Old_age   Always       -       0
205 Shock_Rate_Write_Opern  0x000a   253   252   000    Old_age   Always       -       0
207 Spin_High_Current       0x002a   253   252   000    Old_age   Always       -       0
208 Spin_Buzz               0x002a   253   252   000    Old_age   Always       -       0
209 Offline_Seek_Performnce 0x0024   189   182   000    Old_age   Offline      -       0
 99 Unknown_Attribute       0x0004   253   253   000    Old_age   Offline      -       0
100 Unknown_Attribute       0x0004   253   253   000    Old_age   Offline      -       0
101 Unknown_Attribute       0x0004   253   253   000    Old_age   Offline      -       0
```

The basic S.M.A.R.T. test shows there is a problem on the disk:

```console
gate:~ smartctl --health /dev/hda
=== START OF READ SMART DATA SECTION ===
SMART overall-health self-assessment test result: PASSED
Please note the following marginal Attributes:
ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
203 Run_Out_Cancel          0x000b   253   096   180    Pre-fail  Always   In_the_past 24
```

Let's run the "short" test to do quick test of the disk:

```console
gate:~ smartctl -t short /dev/hda
=== START OF OFFLINE IMMEDIATE AND SELF-TEST SECTION ===
Sending command: "Execute SMART Short self-test routine immediately in off-line mode".
Drive command "Execute SMART Short self-test routine immediately in off-line mode" successful.
Testing has begun.
Please wait 2 minutes for test to complete.
Test will complete after Thu Mar 18 13:10:57 2010

Use smartctl -X to abort test.
```

Here are the results from the previous test:

```console
gate:~ smartctl -l selftest /dev/hda
=== START OF READ SMART DATA SECTION ===
SMART Self-test log structure revision number 1
Num  Test_Description    Status                  Remaining  LifeTime(hours)  LBA_of_first_error
# 1  Short offline       Completed without error       00%      2187         -
# 2  Short offline       Completed without error       00%       469         -
# 3  Short offline       Completed without error       00%       469         -
# 4  Short offline       Completed without error       00%       469         -
# 5  Short offline       Completed without error       00%       469         -
# 6  Short offline       Completed without error       00%       469         -
# 7  Short offline       Completed without error       00%       469         -
# 8  Short offline       Completed without error       00%       469         -
# 9  Short offline       Completed without error       00%       469         -
#10  Short offline       Completed without error       00%       469         -
#11  Short offline       Completed without error       00%       469         -
#12  Short offline       Completed without error       00%       469         -
#13  Short offline       Completed without error       00%       469         -
#14  Short offline       Completed without error       00%       469         -
#15  Short offline       Completed without error       00%       469         -
#16  Short offline       Completed without error       00%       469         -
#17  Short offline       Completed without error       00%       469         -
#18  Short offline       Completed without error       00%       469         -
#19  Short offline       Completed without error       00%       469         -
#20  Short offline       Completed without error       00%       469         -
#21  Short offline       Completed without error       00%       469         -
```

Looks like short test doesn't tell much about errors. Run "long" one:

```console
gate:~ smartctl -t long /dev/hda
=== START OF OFFLINE IMMEDIATE AND SELF-TEST SECTION ===
Sending command: "Execute SMART Extended self-test routine immediately in off-line mode".
Drive command "Execute SMART Extended self-test routine immediately in off-line mode" successful.
Testing has begun.
Please wait 13 minutes for test to complete.
Test will complete after Thu Mar 18 13:24:25 2010

Use smartctl -X to abort test.
```

The "long" test shows the errors:

```console
gate:~ smartctl -l selftest /dev/hda
=== START OF READ SMART DATA SECTION ===
SMART Self-test log structure revision number 1
Num  Test_Description    Status                  Remaining  LifeTime(hours)  LBA_of_first_error
# 1  Short offline       Completed: read failure       60%      2187         12678904
# 2  Extended offline    Completed: read failure       30%      2187         12678904
# 3  Short offline       Completed: read failure       60%      2187         12678901
# 4  Extended offline    Completed: read failure       30%      2187         12678904
# 5  Short offline       Completed without error       00%      2187         -
# 6  Short offline       Completed without error       00%       469         -
# 7  Short offline       Completed without error       00%       469         -
# 8  Short offline       Completed without error       00%       469         -
# 9  Short offline       Completed without error       00%       469         -
#10  Short offline       Completed without error       00%       469         -
#11  Short offline       Completed without error       00%       469         -
#12  Short offline       Completed without error       00%       469         -
#13  Short offline       Completed without error       00%       469         -
#14  Short offline       Completed without error       00%       469         -
#15  Short offline       Completed without error       00%       469         -
#16  Short offline       Completed without error       00%       469         -
#17  Short offline       Completed without error       00%       469         -
#18  Short offline       Completed without error       00%       469         -
#19  Short offline       Completed without error       00%       469         -
#20  Short offline       Completed without error       00%       469         -
#21  Short offline       Completed without error       00%       469         -
```

See all previous errors:

```console
gate:~  smartctl --attributes --log=selftest --quietmode=errorsonly /dev/hda
ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
203 Run_Out_Cancel          0x000b   253   096   180    Pre-fail  Always   In_the_past 66

Num  Test_Description    Status                  Remaining  LifeTime(hours)  LBA_of_first_error
# 1  Short offline       Completed: read failure       60%      2187         12678901
# 2  Extended offline    Completed: read failure       30%      2187         12678904

gate:~  smartctl --log=error --quietmode=errorsonly /dev/hda
ATA Error Count: 2105 (device log contains only the most recent five errors)
Error 2105 occurred at disk power-on lifetime: 2188 hours (91 days + 4 hours)
Error 2104 occurred at disk power-on lifetime: 2188 hours (91 days + 4 hours)
Error 2103 occurred at disk power-on lifetime: 2188 hours (91 days + 4 hours)
Error 2102 occurred at disk power-on lifetime: 2188 hours (91 days + 4 hours)
Error 2101 occurred at disk power-on lifetime: 2188 hours (91 days + 4 hours)
```

## Bad block test

You can see the errors also in the `syslog`:

```console
gate:~ grep LBA /var/log/messages
...
Mar 18 08:34:01 gate kernel: [   74.222868] hda: dma_intr: error=0x40 { UncorrectableError }, LBAsect=4518804, sector=4518798
Mar 18 08:35:08 gate kernel: [  198.366248] hda: dma_intr: error=0x40 { UncorrectableError }, LBAsect=16327415, sector=16327414
Mar 18 08:35:10 gate kernel: [  200.543912] hda: dma_intr: error=0x40 { UncorrectableError }, LBAsect=16327415, sector=16327414
Mar 18 08:36:18 gate kernel: [  268.565562] hda: dma_intr: error=0x40 { UncorrectableError }, LBAsect=16298535, sector=16298534
Mar 18 08:36:20 gate kernel: [  270.662356] hda: dma_intr: error=0x40 { UncorrectableError }, LBAsect=16298535, sector=16298534
Mar 18 08:37:15 gate kernel: [  325.463500] hda: dma_intr: error=0x01 { AddrMarkNotFound }, LBAsect=16285168, sector=16285166
Mar 18 08:37:44 gate kernel: [  354.873957] hda: dma_intr: error=0x40 { UncorrectableError }, LBAsect=3503880, sector=3503878
Mar 18 08:37:49 gate kernel: [  359.932012] hda: dma_intr: error=0x40 { UncorrectableError }, LBAsect=3503880, sector=3503878
...
```

Use `badblock` check as the last, because it's time consuming:

```console
gate:~ time badblocks -s -v -o /tmp/bad_blocks /dev/hda
Checking blocks 0 to 19938239
Checking for bad blocks (read-only test): done
Pass completed, 5 bad blocks found.

real    163m59.908s
user    0m3.712s
sys     0m48.583s

gate:~ cat /tmp/bad_blocks
6601216
6601592
8043696
8149160
10533408
```

[badblocks](https://en.wikipedia.org/wiki/Badblocks) and S.M.A.R.T show errors so
it's pretty clear, that that disk needs to be replaced asap.
The commands I used before tested disk from "hardware" level. Because there is a
RAID 1 in place it was nice opportunity to see what was happening on "software"
level.

## RAID checks

Here is the `fdisk` output for both disks:

```console
gate:~ fdisk -l /dev/hda /dev/hdc

Disk /dev/hda: 20.4 GB, 20416757760 bytes
255 heads, 63 sectors/track, 2482 cylinders
Units = cylinders of 16065 * 512 = 8225280 bytes
Disk identifier: 0x00051324

   Device Boot      Start         End      Blocks   Id  System
/dev/hda1               1           6       48163+  fd  Linux raid autodetect
/dev/hda2               7        2482    19888470   fd  Linux raid autodetect

Disk /dev/hdc: 20.4 GB, 20416757760 bytes
255 heads, 63 sectors/track, 2482 cylinders
Units = cylinders of 16065 * 512 = 8225280 bytes
Disk identifier: 0x0006e1d1

   Device Boot      Start         End      Blocks   Id  System
/dev/hdc1               1           6       48163+  fd  Linux raid autodetect
/dev/hdc2               7        2482    19888470   fd  Linux raid autodetect
```

Before I began to do any high disk utilization operations, it was good to check
used max speed for RAID check. If I had this value "higher" it could really slow
down the server. 1 MB/s is enough for my old disks:

```console
gate:~ echo 1000 > /proc/sys/dev/raid/speed_limit_max
gate:~ cat /etc/sysctl.conf
...
# RAID rebuild min/max speed K/Sec per device
dev.raid.speed_limit_min = 100
dev.raid.speed_limit_max = 1000
```

Start disk check:

```console
gate:~ /usr/share/mdadm/checkarray --all
checkarray: I: check queued for array md0.
checkarray: I: check queued for array md1.

gate:~ cat /proc/mdstat
Personalities : [raid1]
md1 : active raid1 hda2[0] hdc2[1]
      19888384 blocks [2/2] [UU]
        resync=DELAYED

md0 : active raid1 hda1[0] hdc1[1]
      48064 blocks [2/2] [UU]
      [======>..............]  check = 31.9% (16000/48064) finish=0.4min speed=1066K/sec

unused devices: <none>

gate:~ dmesg
...
[41674.362333] md: data-check of RAID array md0
[41674.362399] md: minimum _guaranteed_  speed: 100 KB/sec/disk.
[41674.362447] md: using maximum available idle IO bandwidth (but not more than 1000 KB/sec) for data-check.
[41674.362532] md: using 128k window, over a total of 48064 blocks.
[41674.385200] md: delaying data-check of md1 until md0 has finished (they share one or more physical units)
[41721.793276] md: md0: data-check done.
[41721.851857] md: data-check of RAID array md1
[41721.852088] md: minimum _guaranteed_  speed: 100 KB/sec/disk.
[41721.852140] md: using maximum available idle IO bandwidth (but not more than 1000 KB/sec) for data-check.
[41721.852226] md: using 128k window, over a total of 19888384 blocks.
[41721.856334] RAID1 conf printout:
[41721.856395]  --- wd:2 rd:2
[41721.856439]  disk 0, wo:0, o:1, dev:hda1
[41721.856484]  disk 1, wo:0, o:1, dev:hdc1
[65191.893316] md: md1: data-check done.
[65192.158680] RAID1 conf printout:
[65192.158745]  --- wd:2 rd:2
[65192.158787]  disk 0, wo:0, o:1, dev:hda2
[65192.158829]  disk 1, wo:0, o:1, dev:hdc2
...
</none>
```

To my surprise `mdadm` didn't find any errors :-(

## Disk replacement

The disk needed to be replaced by the new one.

First I had to mark it as failed:

```console
gate:~ mdadm --manage /dev/md0 --fail /dev/hda1
mdadm: set /dev/hda1 faulty in /dev/md0
gate:~ cat /proc/mdstat
Personalities : [raid1]
md1 : active raid1 hda2[0] hdc2[1]
      19888384 blocks [2/2] [UU]

md0 : active raid1 hda1[2](F) hdc1[1]
      48064 blocks [2/1] [_U]

unused devices: <none>
</none>
```

Then I removed it from `/dev/md0`:

```console
gate:~ mdadm --manage /dev/md0 --remove /dev/hda1
mdadm: hot removed /dev/hda1
```

Dmesg:

```console
gate:~ dmesg
...
[142783.600283] raid1: Disk failure on hda1, disabling device.
[142783.600294] raid1: Operation continuing on 1 devices.
[142783.624888] RAID1 conf printout:
[142783.624947]  --- wd:1 rd:2
[142783.624986]  disk 0, wo:1, o:0, dev:hda1
[142783.625029]  disk 1, wo:0, o:1, dev:hdc1
[142783.636136] RAID1 conf printout:
[142783.636203]  --- wd:1 rd:2
[142783.636245]  disk 1, wo:0, o:1, dev:hdc1
[142905.796896] md: unbind<hda1>
[142905.796988] md: export_rdev(hda1)
...
</hda1>
```

I had to do the same procedure for `md1`:

```console
gate:~ mdadm --manage /dev/md1 --fail /dev/hda2
mdadm: set /dev/hda2 faulty in /dev/md1
gate:~ mdadm --manage /dev/md1 --remove /dev/hda2
mdadm: hot removed /dev/hda2
```

Warning email from `mdadm` was sent:

```text
Subject: Fail event on /dev/md0:gate

This is an automatically generated mail message from mdadm
running on gate

A Fail event had been detected on md device /dev/md0.

It could be related to component device /dev/hda1.
```

## After disk change

New disk was installed, OS was up and running - it's time to check bad sectors
on the new one:

```console
gate:~ time badblocks -s -v -w -o /var/tmp/bad_blocks /dev/hda
```

I needed to have the same partitions like on the new "clean" disk like on the
old one. The easiest way is to use `sfdisk`:

```console
gate:~ sfdisk -d /dev/hdc | sfdisk --force /dev/hda
```

Added the partitions to the RAID:

```console
gate:~ mdadm --manage /dev/md0 --add /dev/hda1
gate:~ mdadm --manage /dev/md1 --add /dev/hda2
```

The last step is installing the GRUB to MBR of the new disk. If you forgot about
it, than I will not be able to boot from the "new" `hda` disk if "old" disk
`hdc` fail.

```console
gate:~ grub
root (hd0,0)
setup (hd0)
```

You find fine a lot of great tips regarding "bad sectors" on
[this page](https://smartmontools.sourceforge.net).
