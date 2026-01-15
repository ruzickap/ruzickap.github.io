---
title: Android adb data backup & restore
author: Petr Ruzicka
date: 2012-06-30
categories: [Linux, Android]
tags: [adb, backup, SQLite]
---

MY_BACKUP_PATH=/var/tmp/android_backup

MMS/SMS data:
adb pull /data/data/com.android.providers.telephony/databases/mmssms.db
$MY_BACKUP_PATH

Restore:
adb push $MY_BACKUP_PATH/mmssms.db
/data/data/com.android.providers.telephony/databases/mmssms.db

System WiFi Settings:
adb pull /data/misc/wifi/wpa_supplicant.conf $MY_BACKUP_PATH
adb push $MY_BACKUP_PATH/wpa_supplicant.conf /data/misc/wifi/wpa_supplicant.conf

Call backup:
adb shell sqlite3
/data/data/com.android.providers.contacts/databases/contacts*.db 'select * from
calls' > $MY_BACKUP_PATH/calls
#adb pull /data/local/calls /data/data/dbs/
#adb shell rm /data/local/calls

Restore
adb push $MY_BACKUP_PATH/calls /data/local/
adb shell sqlite3
/data/data/com.android.providers.contacts/databases/contacts*.db import
/data/local/calls ca
adb shell rm /data/local/calls

adb push $MY_BACKUP_PATH/contacts*.db
/data/data/com.android.providers.contacts/databases/

Application: /data/app/
/data/app-private/

Browser settings:
adb push /data/data/com.android.browser/databases/browser.db browser.db
adb pull browser.db /data/data/com.android.browser/databases/browser.db
