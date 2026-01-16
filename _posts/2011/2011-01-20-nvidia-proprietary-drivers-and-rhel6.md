---
title: Nvidia proprietary drivers and RHEL6
author: Petr Ruzicka
date: 2011-01-20
description: https://linux-old.xvx.cz/2011/01/nvidia-proprietary-drivers-and-rhel6/
categories: [Linux, RHEL]
tags: [Nvidia, GRUB, drivers, yum]
---

Sometimes you need to run [Nvidia](https://www.nvidia.com/) proprietary drivers
in various linux distributions.

I was able to run it on standard [RHEL](https://www.redhat.com/) 6.0 installed as
"Desktop" with the following commands:

Update the system and install the necessary packages

```bash
yum update
yum install gcc kernel-devel
reboot
```

Blacklist the [nouveau](https://nouveau.freedesktop.org/) driver

```bash
sed -i '/root=/s|$| rdblacklist=nouveau vga=791|' /boot/grub/grub.conf
echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf
```

Change the initrd image:

```bash
mv "/boot/initramfs-$(uname -r).img" "/boot/initramfs-$(uname -r)-nouveau.img"
dracut "/boot/initramfs-$(uname -r).img" "$(uname -r)"
```

Remove the nouveau driver and reboot:

```bash
yum remove xorg-x11-drv-nouveau
reboot
```

Stop the X server and run the Nvidia installation process from command line

```bash
init 3
chmod +x NVIDIA-Linux-x86-260.19.29.run
./NVIDIA-Linux-x86-260.19.29.run
```

Enjoy :-)
