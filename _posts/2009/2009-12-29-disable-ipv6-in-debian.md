---
title: Disable IPv6 in Debian
author: Petr Ruzicka
date: 2009-12-29
description: ""
categories: [Linux, Debian]
tags: [GRUB, IPv6, networking]
---

> <https://linux-old.xvx.cz/2009/12/disable-ipv6-in-debian/>
{: .prompt-info }

I had a problem with Java Webstart applications, which were using IPv6 by
default. Because I'm not using IPv6 at all I decided to disable this protocol
completely.

There are many pages about how to disable IPv6 under Debian, but most of them
were not working for me.

The easiest one worked well:

Modify `/etc/default/grub`:

```ini
GRUB_CMDLINE_LINUX_DEFAULT="ipv6.disable=1"
```

Don't forget to run `update-grub` after the change (and reboot).

Then if you run

```bash
ip a
```

you should not see any IPv6 addresses...
