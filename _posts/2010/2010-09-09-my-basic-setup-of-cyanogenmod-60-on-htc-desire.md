---
title: My basic setup of CyanogenMod-6.0 on HTC Desire
author: Petr Ruzicka
date: 2010-09-09
description: ""
categories: [Android]
tags: [htc-desire, cyanogenmod, adb]
---

> <https://linux-old.xvx.cz/2010/09/my-basic-setup-of-cyanogenmod-6-0-on-htc-desire/>
{: .prompt-info }

Since I bought my HTC Desire I wanted to put
[CyanogenMod](https://web.archive.org/web/2016/http://www.cyanogenmod.com/) on
it. This ROM is quite popular, but only version 6.0 released last week supports
[HTC Desire](https://web.archive.org/web/20161224225045/https://wiki.cyanogenmod.org/w/bravo_Info).

I'm going to put a few notes here on how I did "post installation" changes like
removing some programs, ssh key config, OpenVPN setup, and a few more.

I don't want to describe here how to install this ROM to the HTC Desire,
because there is nice how-to on their pages:
[Full Update Guide - HTC Desire](https://web.archive.org/web/20161224202150/https://wiki.cyanogenmod.org/w/Install_CM_for_bravo)

Just one remark - If you suffer from signal loss please look at
[this page](https://web.archive.org/web/2012/http://forum.cyanogenmod.com/topic/5437-signal-drops-after-rc2-final/).

Put ssh keys to the phone and start dropbear (SSH server):
(taken from [CyanogenMod Wiki - Connect with SSH](https://web.archive.org/web/2016/http://wiki.cyanogenmod.org/w/Doc:_sshd))

Copy your ssh public key from your Linux box to the phone:

```bash
adb push /home/ruzickap/.ssh/id_rsa.pub /sdcard/authorized_keys
```

Prepare dropbear on the phone:

```bash
adb shell

mkdir -p /data/dropbear/.ssh/

dropbearkey -t rsa -f /data/dropbear/dropbear_rsa_host_key
dropbearkey -t dss -f /data/dropbear/dropbear_dss_host_key

cp /sdcard/authorized_keys /data/dropbear/.ssh/

chmod 755 /data/dropbear /data/dropbear/.ssh
chmod 644 /data/dropbear/dropbear*host_key /data/dropbear/.ssh/authorized_keys

echo "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:/system/sbin:/system/bin:/system/xbin:/system/xbin/bb:/data/local/bin" >>/data/dropbear/.profile

dropbear
```

Remove some useless applications:
(check this page [CyanogenMod Wiki - Barebones](https://web.archive.org/web/2016/http://wiki.cyanogenmod.org/w/Barebones) to see what can be removed)

Reboot to "ClockworkMod recovery" (using Fake Flash by Koush).

Mount `/system` partition:

```bash
adb shell
mount -o nodev,noatime,nodiratime -t yaffs2 /dev/block/mtdblock3 /system
mount /data
```

Backup directories under `/data`:

```bash
BACKUP_DESTINATION="/sdcard/mybackup"
cd /data
mkdir -p $BACKUP_DESTINATION/data/ && \
cp -R `ls /data | egrep -v "dalvik-cache|lost\+found"` $BACKUP_DESTINATION/data/
```

Move applications to sdcard:

```bash
for APK in ApplicationsProvider.apk CarHomeGoogle.apk CarHomeLauncher.apk com.amazon.mp3.apk Development.apk Email.apk Facebook.apk GenieWidget.apk googlevoice.apk Maps.apk PicoTts.apk Protips.apk RomManager.apk SetupWizard.apk SpeechRecorder.apk Stk.apk Street.apk Talk.apk TtsService.apk Twitter.apk VoiceDialer.apk YouTube.apk; do
echo "*** $APK"
mkdir $BACKUP_DESTINATION/$APK && \
mv /system/app/$APK $BACKUP_DESTINATION/$APK/ && \
mv /data/data/`awk -F \" '/'$APK'/ { print $2 }' /data/system/packages.xml` $BACKUP_DESTINATION/$APK/
#/system/bin/pm uninstall `awk -F \" '/'package.apk'/ { print $2 }' /data/system/packages.xml`
done
```

Remove unused audio files:

```bash
for AUDIO in `find /system/media/audio -type f|egrep -v "ui|Alarm_Buzzer.ogg|SpaceSeed.ogg|Doink.ogg|SpaceSeed.ogg|CrayonRock.ogg"`; do
for AUDIO in `find /system/media/audio -type f|egrep -v "ui|pixiedust.ogg"`; do
    echo "*** Removing $AUDIO"
    rm $AUDIO
done
```

Unmount all used filesystems:

```bash
cd /
umount /data /sdcard /system
```

It's all for now... I'm sure I will do more sooner or later, but it's just a few
notes for now.

Enjoy :-)
