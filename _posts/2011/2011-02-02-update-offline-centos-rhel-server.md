---
title: Update offline CentOS-RHEL server
author: Petr Ruzicka
date: 2011-02-02
categories: [Linux, RHEL]
tags: [yum, offline, security-updates]
---

> <https://linux-old.xvx.cz/2011/02/update-offline-centosrhel-server/>
{: .prompt-info }

Sometimes you have a
[RHEL](https://www.redhat.com/rhel/)/[CentOS](https://www.centos.org/) server
which is not connected to the Internet. But you should also install security
updates to prevent local hackers from messing up your system.

I was not able to find a good description of how to do it. Some people are using
proxies - but then you still need some connection to the proxy - which can not
be the case.

Here is my way how I did it....

Let's say there is a server which is offline and doesn't have any connection to
the Internet. Then we need station (or laptop / virtual machine), which has the
same OS as server and is connected to the Internet.

Copy the `/var/lib/rpm` to the station (you can use USB/CD...)

```bash
scp -r /var/lib/rpm root@station:/tmp/
```

Install the download only plugin for yum:

```bash
yum install yum-downloadonly
```

Backup the original rpm directory on the station and replace it with the rpm
directory from the server:

```bash
mv -v /var/lib/rpm /var/lib/rpm.orig
mv -v /tmp/rpm /var/lib/
```

Download updates to `/tmp/rpm_updates` and return back the `/var/lib/rpm`

```bash
mkdir -v /tmp/rpm_updates
yum update --downloadonly --downloaddir /tmp/rpm_updates
rm -rvf /var/lib/rpm
mv -v /var/lib/rpm.orig /var/lib/rpm
```

Transfer the downloaded rpms to the server and update:

```bash
scp -r /tmp/rpm_updates root@server:/tmp/
ssh root@server
rpm -Uvh /tmp/rpm_updates/*
```

...and the server is updated ;-)

This is probably not the best way how to do it, but it's working for me.
