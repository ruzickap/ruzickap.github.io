---
title: Debian with GRUB2 and serial connection
author: Petr Ruzicka
date: 2009-08-05
description: https://linux-old.xvx.cz/2009/08/debian-with-grub2-and-serial-connection/
categories: [Linux, Debian]
tags: [GRUB, serial]
---

Sometimes I'm using the serial connection to my server if anything goes wrong.
It's because I don't have a monitor/TV attached to it.

I had some problems setting it up using Debian in GRUB2 after I upgraded to
grub-pc.

So here is a short way how to do it:

Edit file containing configuration in Debian: `/etc/default/grub`

```ini
# If you change this file, run 'update-grub' afterwards to update
# /boot/grub/grub.cfg.

GRUB_DEFAULT=0
GRUB_TIMEOUT=1
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,9600n8"

# Uncomment to disable graphical terminal (grub-pc only)
GRUB_TERMINAL=serial
GRUB_SERIAL_COMMAND="serial --speed=9600 --unit=0 --word=8 --parity=no --stop=1"

# The resolution used on graphical terminal
# note that you can use only modes which your graphic card supports via VBE
# you can see them in real GRUB with the command `vbeinfo'
#GRUB_GFXMODE=640x480

# Uncomment if you don't want GRUB to pass "root=UUID=xxx" parameter to Linux
#GRUB_DISABLE_LINUX_UUID=true
```

Don't forget to run `update-grub` after change.
