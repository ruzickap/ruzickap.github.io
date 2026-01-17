---
title: PXE server using Dnsmasq and SystemRescueCd with minimal effort
author: Petr Ruzicka
date: 2010-04-11
description: ""
categories: [Linux, Networking]
tags: [pxe, dnsmasq, grub]
---

> <https://linux-old.xvx.cz/2010/04/pxe-server-using-dnsmasq-and-systemrescuecd-with-minimal-effort/>
{: .prompt-info }

If you are using
[DHCP](https://en.wikipedia.org/wiki/Dynamic_Host_Configuration_Protocol) server
in your network environment, it's handy to be able to boot from the network. It
brings you many advantages especially when you are not able to boot the
operating system from the workstation's disk.

I would like to describe my experience with DHCP server called
[Dnsmasq](https://thekelleys.org.uk/dnsmasq/doc.html). This software can also
serve [TFTP](https://en.wikipedia.org/wiki/Trivial_File_Transfer_Protocol)
requests and act as DNS forwarder.

There are many how-to pages on how to set up PXE. In most of them you need
[NFS](https://en.wikipedia.org/wiki/Network_File_System_%28protocol%29),
[xinetd](https://en.wikipedia.org/wiki/Xinetd) or similar CPU/memory
consuming stuff.

You can see how you can set up a working boot environment "only" with the ISO
image of
[SystemRescueCd](https://www.sysresccd.org/) and dnsmasq.

Let's start with installing dnsmasq and downloading the ISO image of
SystemRescueCd:

```bash
aptitude install dnsmasq bzip2
mkdir -vp /home/ftp/pub/distributions
cd /home/ftp/pub/distributions || exit
wget http://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86/1.5.1/systemrescuecd-x86-1.5.1.iso/download
```

Mount ISO file and make it permanent in fstab:

```bash
mkdir -v systemrescuecd tftpboot
echo "$(readlink -f systemrescuecd*.iso) $PWD/systemrescuecd iso9660 ro,loop,auto 0 0" >> /etc/fstab
mount systemrescuecd
```

Fill `tftpboot` directory with necessary files/links:

```bash
mkdir -v tftpboot/pxelinux.cfg
sed 's@initrd=initram.igz@initrd=initram.igz netboot=tftp://192.168.0.1/sysrcd.dat  rootpass=xxxx setkmap=us@' systemrescuecd/isolinux/isolinux.cfg > tftpboot/pxelinux.cfg/default
for FILE in systemrescuecd/isolinux/* systemrescuecd/sysrcd* systemrescuecd/ntpasswd systemrescuecd/bootdisk; do
  ln -vs "../$FILE" "tftpboot/$(basename "$FILE")"
done
wget http://www.kernel.org/pub/linux/utils/boot/syslinux/syslinux-3.86.tar.bz2 -O - |
  tar xvjf - --to-stdout syslinux-3.86/core/pxelinux.0 > tftpboot/pxelinux.0
```

Configure dnsmasq to listen on `eth1`:

```bash
mv -v /etc/dnsmasq.conf /etc/dnsmasq.conf.old
cat << EOF > /etc/dnsmasq.conf
domain-needed
bogus-priv
interface=eth1
bind-interfaces
expand-hosts
domain=linux.xvx.cz
dhcp-range=192.168.0.50,192.168.0.150,12h
dhcp-boot=pxelinux.0
enable-tftp
tftp-root=$PWD/tftpboot
EOF
```

Restart dnsmasq daemon and try to boot over network from computer connected to
`eth1` interface.

```bash
ifconfig eth1 192.168.0.1 netmask 255.255.255.0
dnsmasq --keep-in-foreground --no-daemon --log-queries --log-facility=/tmp/dnsmasq_log --log-dhcp --dhcp-leasefile=/tmp/dhcp-leasefile
```

You should see something like (I included examples for 100 Mbit and 1 Gbit
network to see the speed difference):

{% include embed/youtube.html id='acREwhuPI4c' %}

Another example from [VirtualBox](https://www.virtualbox.org/):

{% include embed/youtube.html id='qOiGtUKO9Z8' %}

Dnsmasq produced this output:

```console
root@debian:/home/ftp/pub/distributions# dnsmasq --keep-in-foreground --no-daemon --log-queries --log-facility=/tmp/dnsmasq_log --log-dhcp --dhcp-leasefile=/tmp/dhcp-leasefile
dnsmasq: started, version 2.52 cachesize 150
dnsmasq: compile time options: IPv6 GNU-getopt DBus I18N DHCP TFTP
dnsmasq-dhcp: DHCP, IP range 192.168.0.50 -- 192.168.0.150, lease time 12h
dnsmasq-tftp: TFTP root is /home/ftp/pub/distributions/tftpboot
dnsmasq: reading /etc/resolv.conf
dnsmasq: using nameserver 208.67.220.220#53
dnsmasq: ignoring nameserver 192.168.0.1 - local interface
dnsmasq: read /etc/hosts - 7 addresses
dnsmasq-dhcp: 3587244887 Available DHCP range: 192.168.0.50 -- 192.168.0.150
dnsmasq-dhcp: 3587244887 Vendor class: PXEClient:Arch:00000:UNDI:002001
dnsmasq-dhcp: 3587244887 DHCPDISCOVER(eth1) 00:13:d4:d1:03:57
dnsmasq-dhcp: 3587244887 DHCPOFFER(eth1) 192.168.0.90 00:13:d4:d1:03:57
dnsmasq-dhcp: 3587244887 requested options: 1:netmask, 2:time-offset, 3:router, 5, 6:dns-server,
dnsmasq-dhcp: 3587244887 requested options: 11, 12:hostname, 13:boot-file-size, 15:domain-name,
dnsmasq-dhcp: 3587244887 requested options: 16:swap-server, 17:root-path, 18:extension-path,
dnsmasq-dhcp: 3587244887 requested options: 43:vendor-encap, 54:server-identifier, 60:vendor-class,
dnsmasq-dhcp: 3587244887 requested options: 67:bootfile-name, 128, 129, 130, 131, 132,
dnsmasq-dhcp: 3587244887 requested options: 133, 134, 135
dnsmasq-dhcp: 3587244887 tags: eth1
dnsmasq-dhcp: 3587244887 next server: 192.168.0.1
dnsmasq-dhcp: 3587244887 sent size:  1 option: 53:message-type  02
dnsmasq-dhcp: 3587244887 sent size:  4 option: 54:server-identifier  192.168.0.1
dnsmasq-dhcp: 3587244887 sent size:  4 option: 51:lease-time  00:00:a8:c0
dnsmasq-dhcp: 3587244887 sent size:  4 option: 58:T1  00:00:54:60
dnsmasq-dhcp: 3587244887 sent size:  4 option: 59:T2  00:00:93:a8
dnsmasq-dhcp: 3587244887 sent size: 11 option: 67:bootfile-name  70:78:65:6c:69:6e:75:78:2e:30:00
dnsmasq-dhcp: 3587244887 sent size:  4 option:  1:netmask  255.255.255.0
dnsmasq-dhcp: 3587244887 sent size:  4 option: 28:broadcast  192.168.0.255
dnsmasq-dhcp: 3587244887 sent size:  4 option:  3:router  192.168.0.1
dnsmasq-dhcp: 3587244887 sent size:  4 option:  6:dns-server  192.168.0.1
dnsmasq-dhcp: 3587244887 sent size: 13 option: 15:domain-name  linux.xvx.cz
dnsmasq-dhcp: 3587244887 Available DHCP range: 192.168.0.50 -- 192.168.0.150
dnsmasq-dhcp: 3587244887 Vendor class: PXEClient:Arch:00000:UNDI:002001
dnsmasq-dhcp: 3587244887 DHCPREQUEST(eth1) 192.168.0.90 00:13:d4:d1:03:57
dnsmasq-dhcp: 3587244887 DHCPACK(eth1) 192.168.0.90 00:13:d4:d1:03:57
dnsmasq-dhcp: 3587244887 requested options: 1:netmask, 2:time-offset, 3:router, 5, 6:dns-server,
dnsmasq-dhcp: 3587244887 requested options: 11, 12:hostname, 13:boot-file-size, 15:domain-name,
dnsmasq-dhcp: 3587244887 requested options: 16:swap-server, 17:root-path, 18:extension-path,
dnsmasq-dhcp: 3587244887 requested options: 43:vendor-encap, 54:server-identifier, 60:vendor-class,
dnsmasq-dhcp: 3587244887 requested options: 67:bootfile-name, 128, 129, 130, 131, 132,
dnsmasq-dhcp: 3587244887 requested options: 133, 134, 135
dnsmasq-dhcp: 3587244887 tags: eth1
dnsmasq-dhcp: 3587244887 next server: 192.168.0.1
dnsmasq-dhcp: 3587244887 sent size:  1 option: 53:message-type  05
dnsmasq-dhcp: 3587244887 sent size:  4 option: 54:server-identifier  192.168.0.1
dnsmasq-dhcp: 3587244887 sent size:  4 option: 51:lease-time  00:00:a8:c0
dnsmasq-dhcp: 3587244887 sent size:  4 option: 58:T1  00:00:54:60
dnsmasq-dhcp: 3587244887 sent size:  4 option: 59:T2  00:00:93:a8
dnsmasq-dhcp: 3587244887 sent size: 11 option: 67:bootfile-name  70:78:65:6c:69:6e:75:78:2e:30:00
dnsmasq-dhcp: 3587244887 sent size:  4 option:  1:netmask  255.255.255.0
dnsmasq-dhcp: 3587244887 sent size:  4 option: 28:broadcast  192.168.0.255
dnsmasq-dhcp: 3587244887 sent size:  4 option:  3:router  192.168.0.1
dnsmasq-dhcp: 3587244887 sent size:  4 option:  6:dns-server  192.168.0.1
dnsmasq-dhcp: 3587244887 sent size: 13 option: 15:domain-name  linux.xvx.cz
dnsmasq-tftp: sent /home/ftp/pub/distributions/tftpboot/pxelinux.0 to 192.168.0.90
dnsmasq-tftp: error 0 TFTP Aborted received from 192.168.0.90
dnsmasq-tftp: failed sending /home/ftp/pub/distributions/tftpboot/pxelinux.0 to 192.168.0.90
dnsmasq-tftp: sent /home/ftp/pub/distributions/tftpboot/pxelinux.0 to 192.168.0.90
dnsmasq-tftp: file /home/ftp/pub/distributions/tftpboot/pxelinux.cfg/28ce5d8a-0000-0080-385d-ff0000004746 not found
dnsmasq-tftp: file /home/ftp/pub/distributions/tftpboot/pxelinux.cfg/01-00-13-d4-d1-03-57 not found
dnsmasq-tftp: file /home/ftp/pub/distributions/tftpboot/pxelinux.cfg/C0A8005A not found
dnsmasq-tftp: file /home/ftp/pub/distributions/tftpboot/pxelinux.cfg/C0A8005 not found
dnsmasq-tftp: file /home/ftp/pub/distributions/tftpboot/pxelinux.cfg/C0A800 not found
dnsmasq-tftp: file /home/ftp/pub/distributions/tftpboot/pxelinux.cfg/C0A80 not found
dnsmasq-tftp: file /home/ftp/pub/distributions/tftpboot/pxelinux.cfg/C0A8 not found
dnsmasq-tftp: file /home/ftp/pub/distributions/tftpboot/pxelinux.cfg/C0A not found
dnsmasq-tftp: file /home/ftp/pub/distributions/tftpboot/pxelinux.cfg/C0 not found
dnsmasq-tftp: file /home/ftp/pub/distributions/tftpboot/pxelinux.cfg/C not found
dnsmasq-tftp: sent /home/ftp/pub/distributions/tftpboot/pxelinux.cfg/default to 192.168.0.90
dnsmasq-tftp: sent /home/ftp/pub/distributions/tftpboot/f1boot.msg to 192.168.0.90
dnsmasq-tftp: sent /home/ftp/pub/distributions/tftpboot/rescuecd to 192.168.0.90
dnsmasq-tftp: sent /home/ftp/pub/distributions/tftpboot/initram.igz to 192.168.0.90
dnsmasq-dhcp: 804374645 Available DHCP range: 192.168.0.50 -- 192.168.0.150
dnsmasq-dhcp: 804374645 Vendor class: udhcp 1.15.3
dnsmasq-dhcp: 804374645 DHCPDISCOVER(eth1) 00:13:d4:d1:03:57
dnsmasq-dhcp: 804374645 DHCPOFFER(eth1) 192.168.0.90 00:13:d4:d1:03:57
dnsmasq-dhcp: 804374645 requested options: 1:netmask, 3:router, 6:dns-server, 12:hostname,
dnsmasq-dhcp: 804374645 requested options: 15:domain-name, 28:broadcast, 42:ntp-server
dnsmasq-dhcp: 804374645 tags: eth1
dnsmasq-dhcp: 804374645 bootfile name: pxelinux.0
dnsmasq-dhcp: 804374645 next server: 192.168.0.1
dnsmasq-dhcp: 804374645 sent size:  1 option: 53:message-type  02
dnsmasq-dhcp: 804374645 sent size:  4 option: 54:server-identifier  192.168.0.1
dnsmasq-dhcp: 804374645 sent size:  4 option: 51:lease-time  00:00:a8:c0
dnsmasq-dhcp: 804374645 sent size:  4 option: 58:T1  00:00:54:60
dnsmasq-dhcp: 804374645 sent size:  4 option: 59:T2  00:00:93:a8
dnsmasq-dhcp: 804374645 sent size:  4 option:  1:netmask  255.255.255.0
dnsmasq-dhcp: 804374645 sent size:  4 option: 28:broadcast  192.168.0.255
dnsmasq-dhcp: 804374645 sent size:  4 option:  3:router  192.168.0.1
dnsmasq-dhcp: 804374645 sent size:  4 option:  6:dns-server  192.168.0.1
dnsmasq-dhcp: 804374645 sent size: 13 option: 15:domain-name  linux.xvx.cz
dnsmasq-dhcp: 804374645 Available DHCP range: 192.168.0.50 -- 192.168.0.150
dnsmasq-dhcp: 804374645 Vendor class: udhcp 1.15.3
dnsmasq-dhcp: 804374645 DHCPREQUEST(eth1) 192.168.0.90 00:13:d4:d1:03:57
dnsmasq-dhcp: 804374645 DHCPACK(eth1) 192.168.0.90 00:13:d4:d1:03:57
dnsmasq-dhcp: 804374645 requested options: 1:netmask, 3:router, 6:dns-server, 12:hostname,
dnsmasq-dhcp: 804374645 requested options: 15:domain-name, 28:broadcast, 42:ntp-server
dnsmasq-dhcp: 804374645 tags: eth1
dnsmasq-dhcp: 804374645 bootfile name: pxelinux.0
dnsmasq-dhcp: 804374645 next server: 192.168.0.1
dnsmasq-dhcp: 804374645 sent size:  1 option: 53:message-type  05
dnsmasq-dhcp: 804374645 sent size:  4 option: 54:server-identifier  192.168.0.1
dnsmasq-dhcp: 804374645 sent size:  4 option: 51:lease-time  00:00:a8:c0
dnsmasq-dhcp: 804374645 sent size:  4 option: 58:T1  00:00:54:60
dnsmasq-dhcp: 804374645 sent size:  4 option: 59:T2  00:00:93:a8
dnsmasq-dhcp: 804374645 sent size:  4 option:  1:netmask  255.255.255.0
dnsmasq-dhcp: 804374645 sent size:  4 option: 28:broadcast  192.168.0.255
dnsmasq-dhcp: 804374645 sent size:  4 option:  3:router  192.168.0.1
dnsmasq-dhcp: 804374645 sent size:  4 option:  6:dns-server  192.168.0.1
dnsmasq-dhcp: 804374645 sent size: 13 option: 15:domain-name  linux.xvx.cz
dnsmasq-tftp: sent /home/ftp/pub/distributions/tftpboot/sysrcd.md5 to 192.168.0.90
dnsmasq-tftp: sent /home/ftp/pub/distributions/tftpboot/sysrcd.dat to 192.168.0.90
```

To enable [NAT](https://en.wikipedia.org/wiki/Network_address_translation) and
routing for the hosts run these commands:

```bash
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sed --in-place=.old 's/^#\(net.ipv4.ip_forward=1\)/\1/' /etc/sysctl.conf
sysctl -p
```

The SystemRescueCd guys did a great job. If you have similar PXE SystemRescueCd
installation like I described above it's handy to put these lines into
[GRUB2](https://en.wikipedia.org/wiki/GNU_GRUB) configuration to be able to boot
it when something goes wrong with the Linux box:

```bash
cat << EOF >> /etc/grub.d/40_custom

menuentry "SystemRescueCd 1.5.1" {
    loopback loop /home/ftp/pub/distributions/systemrescuecd-x86-1.5.1.iso
    linux (loop)/isolinux/rescue64 docache setkmap=us rootpass=xxxx isoloop=/home/ftp/pub/distributions/systemrescuecd-x86-1.5.1.iso rdinit=/linuxrc2
    initrd (loop)/isolinux/initram.igz
}
EOF

update-grub
```

Good luck ;-)
