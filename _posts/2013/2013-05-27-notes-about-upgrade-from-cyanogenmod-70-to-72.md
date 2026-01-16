---
title: Notes about upgrade from CyanogenMod 7.0 to 7.2
author: Petr Ruzicka
date: 2013-05-27
categories: [Linux, Android]
tags: [HTC-Desire, CyanogenMod, adb, backup]
---

> Not completed...
{: .prompt-info }

I decided to upgrade my "old" CyanogenMod 7.0 on my HTC Desire to the latest and
"greatest" 7.2 version.

The steps how to do the upgrade were mentioned on the CyanogenMod WiKi and I
don't want to repeat them here.

What is important for me is the part about "Wipe data/factory reset". This is
recommended to do it before updating and it's also mentioned on the wiki page.

You can use many tools to backup/restore your data like SMS, Call Log,
application's settings and other data.

But I prefer to do it myself using command line (adb)...

## Backup part executed on your linux machine

```bash
MY_BACKUP_PATH=/var/tmp/android_backup
test -d $MY_BACKUP_PATH || mkdir $MY_BACKUP_PATH
```

Backup MMS/SMS data:

```bash
adb shell sqlite3 /data/data/com.android.providers.telephony/databases/mmssms.db 'select * from sms' > $MY_BACKUP_PATH/sms
```

Backup System WiFi Settings:

```bash
adb pull /data/misc/wifi/wpa_supplicant.conf $MY_BACKUP_PATH
```

Backup Call log:

```bash
adb shell sqlite3 /data/data/com.android.providers.contacts/databases/contacts*.db 'select * from calls' > $MY_BACKUP_PATH/calls
```

Backup browser settings:

```bash
adb shell sqlite3 /data/data/com.android.browser/databases/browser.db 'select * from bookmarks' > $MY_BACKUP_PATH/bookmarks
```

Backup some apps settings:

```bash
adb pull /data/data/cgeo.geocaching/shared_prefs/cgeo.geocaching_preferences.xml $MY_BACKUP_PATH
adb pull /data/data/cz.vojtisek.freesmssender/shared_prefs/cz.vojtisek.freesmssender_preferences.xml $MY_BACKUP_PATH
adb pull /data/data/com.google.android.maps.mytracks/shared_prefs/SettingsActivity.xml $MY_BACKUP_PATH
adb pull /data/data/com.google.android.maps.mytracks/databases/mytracks.db $MY_BACKUP_PATH
adb pull /data/data/ru.org.amip.ClockSync/shared_prefs/ru.org.amip.ClockSync_preferences.xml $MY_BACKUP_PATH
adb pull /data/data/menion.android.locus.pro/shared_prefs/menion.android.locus.pro_preferences.xml $MY_BACKUP_PATH
adb pull /data/data/eu.inmite.apps.smsjizdenka/databases/smsjizdenka.db $MY_BACKUP_PATH
adb pull /data/data/com.prey/shared_prefs/com.prey_preferences.xml $MY_BACKUP_PATH
adb pull /data/data/com.newsrob/shared_prefs/com.newsrob_preferences.xml $MY_BACKUP_PATH
adb pull /data/data/com.androidlost/shared_prefs/c2dmPref.xml $MY_BACKUP_PATH
adb pull /data/data/com.android.keepass/shared_prefs/com.android.keepass_preferences.xml $MY_BACKUP_PATH
```

### Restore part + some additional configurations

Configure dropbear (ssh) on the phone:

```bash
adb remount
adb push /home/pruzicka/.ssh/id_rsa.pub /sdcard/authorized_keys
adb shell

mkdir -p /data/dropbear/.ssh/

cp /sdcard/authorized_keys /data/dropbear/.ssh/

chmod 755 /data/dropbear
chmod 700 /data/dropbear/.ssh
chmod 600 /data/dropbear/.ssh/authorized_keys

dropbearkey -t rsa -f /data/dropbear/dropbear_rsa_host_key
dropbearkey -t dss -f /data/dropbear/dropbear_dss_host_key

#echo "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:/system/sbin:/system/bin:/system/xbin:/system/xbin/bb:/data/local/bin" >>/data/dropbear/.profile

cat >> /etc/init.local.rc << EOF

# start Dropbear (ssh server) service on boot
service sshd /system/xbin/dropbear -s
   user  root
   group root
   oneshot
EOF

rm /system/app/RomManager.apk
```

Set the default backup directory:

```bash
MY_BACKUP_PATH=/var/tmp/android_backup
```

Restore System WiFi Settings:

```bash
adb push $MY_BACKUP_PATH/wpa_supplicant.conf /data/misc/wifi/
adb shell chown wifi:wifi /data/misc/wifi/wpa_supplicant.conf
```

Restore Call log:

```bash
adb push $MY_BACKUP_PATH/calls /sdcard/
adb shell sqlite3 /data/data/com.android.providers.contacts/databases/contacts*.db '.import /sdcard/calls calls'
```

Restore some apps settings:

```bash
adb shell mkdir -p /data/data/cgeo.geocaching/shared_prefs/
adb push $MY_BACKUP_PATH/cgeo.geocaching_preferences.xml /data/data/cgeo.geocaching/shared_prefs/
adb shell mkdir -p /data/data/cz.vojtisek.freesmssender/{shared_prefs,databases}
adb push $MY_BACKUP_PATH/cz.vojtisek.freesmssender_preferences.xml /data/data/cz.vojtisek.freesmssender/shared_prefs/
adb push $MY_BACKUP_PATH/freesmssender /data/data/cz.vojtisek.freesmssender/databases/
adb shell mkdir -p /data/data/com.google.android.maps.mytracks/{shared_prefs,databases}
adb push $MY_BACKUP_PATH/SettingsActivity.xml /data/data/com.google.android.maps.mytracks/shared_prefs/
adb push $MY_BACKUP_PATH/mytracks.db /data/data/com.google.android.maps.mytracks/databases/
adb shell mkdir -p /data/data/ru.org.amip.ClockSync/shared_prefs/
adb push $MY_BACKUP_PATH/ru.org.amip.ClockSync_preferences.xml /data/data/ru.org.amip.ClockSync/shared_prefs/
adb shell mkdir -p /data/data/menion.android.locus.pro/shared_prefs/
adb push $MY_BACKUP_PATH/menion.android.locus.pro_preferences.xml /data/data/menion.android.locus.pro/shared_prefs/
adb shell mkdir -p /data/data/eu.inmite.apps.smsjizdenka/databases/
adb push $MY_BACKUP_PATH/smsjizdenka.db  /data/data/eu.inmite.apps.smsjizdenka/databases/
adb shell mkdir -p /data/data/com.prey/shared_prefs/
adb push $MY_BACKUP_PATH/com.prey_preferences.xml /data/data/com.prey/shared_prefs/
adb shell mkdir -p /data/data/com.newsrob/shared_prefs/
adb push $MY_BACKUP_PATH/com.newsrob_preferences.xml /data/data/com.newsrob/shared_prefs/
adb shell mkdir -p /data/data/com.androidlost/shared_prefs/
adb push $MY_BACKUP_PATH/c2dmPref.xml /data/data/com.androidlost/shared_prefs/
adb shell mkdir -p /data/data/com.android.keepass/shared_prefs/
adb push $MY_BACKUP_PATH/com.android.keepass_preferences.xml /data/data/com.android.keepass/shared_prefs/
```

Install the applications S2E, My Tracks, Free SMS Sender, c:geo and the
others...

Fix all permissions and reboot:

```bash
adb shell fix_permissions
adb shell 'for APP in CarHomeGoogle.apk Email.apk GenieWidget.apk RomManager.apk Stk.apk Talk.apk; do rm -f /system/app/$APP; done'

adb reboot
```

Maybe you are asking why not to just copy the ".db" files (like it's mentioned
on most of the other pages).
-> the reason is, because the structure of the sqlite db changed between CM
versions and that's the reason why simple copy of the .db files is not working.

Restore SMS data:

```bash
adb push $MY_BACKUP_PATH/sms /sdcard/
adb shell sqlite3 /data/data/com.android.providers.telephony/databases/mmssms.db '.import /sdcard/sms sms'
```

Restore browser settings:

```bash
adb push $MY_BACKUP_PATH/bookmarks /sdcard/
adb shell sqlite3 /data/data/com.android.browser/databases/browser.db '.import /sdcard/bookmarks bookmarks'
```
