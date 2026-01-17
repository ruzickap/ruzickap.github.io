---
title: Root HTC Desire under Debian
author: Petr Ruzicka
date: 2010-05-04
description: ""
categories: [Android]
tags: [htc-desire, adb]
---

> <https://linux-old.xvx.cz/2010/05/root-htc-desire-under-debian/>
{: .prompt-info }

Two weeks ago I bought HTC Desire cell phone and I decided to get root on it.
Rooting guide for this phone was published a few days ago, but most of it is
"windows only".

Here you can find out how to get root on the HTC Desire using Debian.

- Download the zip file from the HTC Desire rooting guide and unzip it:

  ```bash
  mkdir -v /var/tmp/android
  cd /var/tmp/android
  wget http://www.romraid.com/paul/bravo/r4-desire-root.zip
  unzip r4-desire-root.zip
  ```

- If you are using a 64-bit version of Debian, please install ia32-libs
  first, because [adb](https://developer.android.com/guide/developing/tools/adb.html)
  binary is 32-bit.

  ```bash
  apt-get install ia32-libs
  ```

- Enable USB debug mode in your phone by pressing
  *Settings -> Applications -> Development -> USB debugging*
  and get the CID number:

  ```bash
  cd /var/tmp/android || exit
  ./adb-linux shell cat /sys/class/mmc_host/mmc1/mmc1:*/cid
  03534453553034478001bada0400a1f2
  ```

- Put the output string to the following page: [https://hexrev.soaa.me/](https://hexrev.soaa.me/)

- You get another number (`00a10004daba01804734305553445303`) which you need
  to put to a GoldCard generator form together with your email address.
  Then you should receive email with your GoldCard image `goldcard.img`.

- Connect your phone to the computer in "*Disk drive*" mode and put this
  image to your microSD card. (Backup your data from the card before running
  this command!)

  ```console
  dd if=/var/tmp/goldcard.img of=/dev/mmcblk1
  0+1 records in
  0+1 records out
  384 bytes (384 B) copied, 0.00537284 s, 71.5 kB/s
  ```

- Turn off your HTC Desire and turn it back on by holding the "*back*"
  button. You should see "*FASTBOOT*" written on the screen in a red box.
  Connect your phone to the PC and run:

  ```console
  cd /var/tmp/android || exit
  ./step1-linux.sh
  Desire Root Step 1

  Erasing cache and rebooting in RUU mode...

  erasing 'cache'... OKAY
  ... OKAY

  About to start flash...
  < waiting for device >
  sending 'zip' (137446 KB)... OKAY
  writing 'zip'... INFOadopting the signature contained in this image...
  INFOsignature checking...
  INFOzip header checking...
  INFOzip info parsing...
  INFOchecking model ID...
  INFOchecking custom ID...
  INFOchecking main version...
  INFOstart image[hboot] unzipping for pre-update check...
  INFOstart image[hboot] flushing...
  INFO[RUU]WP,hboot,0
  INFO[RUU]WP,hboot,100
  INFOstart image[radio] unzipping for pre-update...
  INFOstart image[radio] flushing...
  INFO[RUU]WP,radio,0
  INFO[RUU]WP,radio,6
  INFO[RUU]WP,radio,14
  INFO[RUU]WP,radio,19
  INFO[RUU]WP,radio,27
  INFO[RUU]WP,radio,36
  INFO[RUU]WP,radio,44
  INFO[RUU]WP,radio,51
  INFO[RUU]WP,radio,59
  INFO[RUU]WP,radio,100
  FAILED (remote: 90 hboot pre-update! please flush image again immediately)
  < waiting for device >
  sending 'zip' (137446 KB)... OKAY
  writing 'zip'... INFOadopting the signature contained in this image...
  INFOsignature checking...
  INFOzip header checking...
  INFOzip info parsing...
  INFOchecking model ID...
  INFOchecking custom ID...
  INFOchecking main version...
  INFOstart image[boot] unzipping & flushing...
  INFO[RUU]UZ,boot,0
  INFO[RUU]UZ,boot,40
  INFO[RUU]UZ,boot,85
  INFO[RUU]UZ,boot,100
  INFO[RUU]WP,boot,0
  INFO[RUU]WP,boot,45
  INFO[RUU]WP,boot,90
  INFO[RUU]WP,boot,100
  INFOstart image[rcdata] unzipping & flushing...
  INFO[RUU]UZ,rcdata,0
  INFO[RUU]WP,rcdata,0
  INFO[RUU]WP,rcdata,100
  INFOstart image[recovery] unzipping & flushing...
  INFO[RUU]UZ,recovery,0
  INFO[RUU]UZ,recovery,24
  INFO[RUU]UZ,recovery,44
  INFO[RUU]UZ,recovery,65
  INFO[RUU]UZ,recovery,93
  INFO[RUU]UZ,recovery,100
  INFO[RUU]WP,recovery,0
  INFO[RUU]WP,recovery,22
  INFO[RUU]WP,recovery,44
  INFO[RUU]WP,recovery,67
  INFO[RUU]WP,recovery,89
  INFO[RUU]WP,recovery,100
  INFOstart image[sp1] unzipping & flushing...
  INFO[RUU]UZ,sp1,0
  INFO[RUU]UZ,sp1,100
  INFO[RUU]WP,sp1,0
  INFO[RUU]WP,sp1,100
  INFOstart image[system] unzipping & flushing...
  INFO[RUU]UZ,system,0
  INFO[RUU]UZ,system,3
  INFO[RUU]UZ,system,7
  INFO[RUU]UZ,system,12
  INFO[RUU]UZ,system,16
  INFO[RUU]UZ,system,20
  INFO[RUU]UZ,system,25
  INFO[RUU]UZ,system,29
  INFO[RUU]UZ,system,33
  INFO[RUU]UZ,system,37
  INFO[RUU]UZ,system,41
  INFO[RUU]UZ,system,45
  INFO[RUU]UZ,system,50
  INFO[RUU]UZ,system,54
  INFO[RUU]UZ,system,58
  INFO[RUU]UZ,system,62
  INFO[RUU]UZ,system,66
  INFO[RUU]WP,system,0
  INFO[RUU]WP,system,66
  INFO[RUU]UZ,system,66
  INFO[RUU]UZ,system,68
  INFO[RUU]UZ,system,70
  INFO[RUU]UZ,system,72
  INFO[RUU]UZ,system,74
  INFO[RUU]UZ,system,76
  INFO[RUU]UZ,system,78
  INFO[RUU]UZ,system,80
  INFO[RUU]UZ,system,83
  INFO[RUU]UZ,system,85
  INFO[RUU]UZ,system,87
  INFO[RUU]UZ,system,89
  INFO[RUU]UZ,system,91
  INFO[RUU]UZ,system,93
  INFO[RUU]UZ,system,96
  INFO[RUU]UZ,system,98
  INFO[RUU]UZ,system,100
  INFO[RUU]WP,system,66
  INFO[RUU]WP,system,68
  INFO[RUU]WP,system,70
  INFO[RUU]WP,system,72
  INFO[RUU]WP,system,74
  INFO[RUU]WP,system,76
  INFO[RUU]WP,system,78
  INFO[RUU]WP,system,80
  INFO[RUU]WP,system,83
  INFO[RUU]WP,system,85
  INFO[RUU]WP,system,87
  INFO[RUU]WP,system,89
  INFO[RUU]WP,system,91
  INFO[RUU]WP,system,94
  INFO[RUU]WP,system,96
  INFO[RUU]WP,system,98
  INFO[RUU]WP,system,100
  INFOstart image[userdata] unzipping & flushing...
  INFO[RUU]UZ,userdata,0
  INFO[RUU]UZ,userdata,100
  INFO[RUU]WP,userdata,0
  INFO[RUU]WP,userdata,100
  OKAY

  Rebooting to bootloader...

  rebooting into bootloader... OKAY

  Step 1 complete - now use the bootloader menu to enter recovery mode.

  To do this, press the power button, wait a few seconds, then use the
  volume keys and power button to select the RECOVERY option.
  ```

- Now navigate to "*BOOTLOADER*" using the volume keys and use power
  button to select. Then select "*RECOVERY*" and press power again.

  Wait 10 seconds until the white HTC screen disappears and run:

  ```console
  time ./step2-linux.sh
  Desire Root Step 2

  Pushing required files to device...

  * daemon not running. starting it now *
  * daemon started successfully *
  push: files/sbin/sdparted -> /sbin/sdparted
  push: files/sbin/mkyaffs2image -> /sbin/mkyaffs2image
  push: files/sbin/toolbox -> /sbin/toolbox
  push: files/sbin/busybox -> /sbin/busybox
  push: files/sbin/adbd -> /sbin/adbd
  push: files/sbin/flash_image -> /sbin/flash_image
  push: files/sbin/fix_permissions -> /sbin/fix_permissions
  push: files/sbin/um -> /sbin/um
  push: files/sbin/parted -> /sbin/parted
  push: files/sbin/wipe -> /sbin/wipe
  push: files/sbin/log2sd -> /sbin/log2sd
  push: files/sbin/tune2fs -> /sbin/tune2fs
  push: files/sbin/mke2fs -> /sbin/mke2fs
  push: files/sbin/reboot -> /sbin/reboot
  push: files/sbin/unyaffs -> /sbin/unyaffs
  push: files/sbin/nandroid-mobile.sh -> /sbin/nandroid-mobile.sh
  push: files/sbin/dump_image -> /sbin/dump_image
  push: files/sbin/ums_toggle -> /sbin/ums_toggle
  push: files/sbin/e2fsck -> /sbin/e2fsck
  push: files/sbin/recovery -> /sbin/recovery
  push: files/sbin/backuptool.sh -> /sbin/backuptool.sh
  push: files/sbin/fs -> /sbin/fs
  push: files/etc/mtab -> /etc/mtab
  push: files/etc/fstab -> /etc/fstab
  push: files/system/lib/libc.so -> /system/lib/libc.so
  push: files/system/lib/libcutils.so -> /system/lib/libcutils.so
  push: files/system/lib/libm.so -> /system/lib/libm.so
  push: files/system/lib/liblog.so -> /system/lib/liblog.so
  push: files/system/lib/libstdc++.so -> /system/lib/libstdc++.so
  push: files/system/bin/sh -> /system/bin/sh
  push: files/system/bin/linker -> /system/bin/linker
  31 files pushed. 0 files skipped.
  1944 KB/s (3709881 bytes in 1.863s)

  Pushing update file to device sdcard - this may take a few minutes...

  1903 KB/s (126444599 bytes in 64.861s)

  Now wipe and apply rootedupdate.zip from the recovery image menu.

  real    1m9.999s
  user    0m0.012s
  sys     0m0.088s
  ```

- Navigate to "*Wipe*" option using optical trackball and continue with
  "*Wipe Data/Factory Reset*" - this will erase all the data in the phone!

  Then go back to the main recovery menu by pressing volume (-) button and
  select "*Flash zip from sdcard*" and choose "*rootedupdate.zip*".

Then your phone will be flashed and you can select "*Reboot system now*" to get
back to the !rooted! phone.

You can check your Software information to see the current version of the ROM
`1.15.405.4` by selecting *Settings -> About phone -> Software information ->
Software number*.

Good luck ;-)
