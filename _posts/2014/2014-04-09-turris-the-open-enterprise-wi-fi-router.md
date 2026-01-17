---
title: Turris - The Open Enterprise Wi-Fi Router
author: Petr Ruzicka
date: 2014-04-09
description: Turris - The Open Enterprise Wi-Fi Router
categories: [OpenWrt]
tags: [wifi, router, turris, nic.cz, nic, open, hardware]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2014/04/turris-open-enterprise-wi-fi-router.html)
{: .prompt-info }

A few months ago I joined the Turris project
([turris.cz](https://www.turris.cz/en/)) which is a not-for-profit research
project of [CZ.NIC](https://www.nic.cz/). I don't want to describe the details of
the project, because you can find it on its web page. In short the company
standing behind the project takes care of Internet security and their idea
was to measure the number of attacks / suspicious traffic by giving the wifi
routers
to the participants.

The wifi router was designed by the company and it's quite a powerful machine
that costs $600. In the first "round" some project members got the wifi router
for free so I would like to share here the details about it, because it's open
hardware/software platform.

## Hardware

The details about the hardware including design and manufacture data is
published under the terms of the [CERN Open Hardware
License](https://web.archive.org/web/20140510092123/http://www.ohwr.org/projects/cernohl/wiki) and can be found here:
[Hardware documentation](https://web.archive.org/web/20160321003446/https://www.turris.cz/en/hardware-documentation).
These details are really nice, because everybody can look at it and improve...

Here are some pictures of how the router looks:

![Turris router front view in metal enclosure](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165738.jpg)

The well-designed metal box looks much better than any cheap routers I worked
with before.

Another photo showing it from the back side:

![Turris router back view showing ports](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-170025.jpg)

Let's see the hardware side - which is really interesting:

- [Processor Freescale P2020](https://web.archive.org/web/20130903204204/http://www.freescale.com/webapp/sps/site/prod_summary.jsp?code=P2020) running at 1200 MHz
- 2 GB of DDR3 RAM in a SO-DIMM slot
- 16 MB NOR and 256 MB NAND flash
- Dedicated gigabit WAN and 5 gigabit LAN ports (using the QCA8337N switch chip)
- Wifi 802.11a/b/g/n with 3x3 MIMO and removable external antennas
- 2x USB 2.0 port
- 1 free miniPCIe slot
- UART, SPI and I2C connected to a pin-header for easy customization
- Power consumption is 9.5 W without load, 12.5 W with CPU load and 14 W with
maximum wired and Wifi network load. Measured power consumption includes the
supplied power adapter.

## Software - OpenWrt

The most important part (at least for me) is - the router is delivered with
preinstalled [OpenWrt](https://openwrt.org/). The router itself was designed to
"fit" to this Linux distribution. Again all software used can be found in git
repositories: <https://gitlab.labs.nic.cz/public/projects?search=turris>

The details about used software are here: <https://www.turris.cz/en/software>

Once you turn on the router you have to finish the wizard which will help you
do the basic configuration and register the router.

After the registration you can see these stats, collected by router and sent to
the NIC.cz.

Screenshots from wizard are in the photo gallery at the end.

Here are some outputs of the commands executed on the fresh router, which may be
interesting:

```console
root@turris:~# ifconfig -a
br-lan    Link encap:Ethernet  HWaddr D8:58:D7:00:02:DC
          inet addr:192.168.1.1  Bcast:192.168.1.255  Mask:255.255.255.0
          inet6 addr: fe80::da58:d7ff:fe00:2dc/64 Scope:Link
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:475 errors:0 dropped:0 overruns:0 frame:0
          TX packets:389 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:0
          RX bytes:41385 (40.4 KiB)  TX bytes:155374 (151.7 KiB)

eth0      Link encap:Ethernet  HWaddr D8:58:D7:00:02:DC
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:7 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000
          RX bytes:0 (0.0 B)  TX bytes:892 (892.0 B)
          Base address:0xa000

eth1      Link encap:Ethernet  HWaddr D8:58:D7:00:02:DD
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:6 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000
          RX bytes:0 (0.0 B)  TX bytes:742 (742.0 B)
          Base address:0xc000

eth2      Link encap:Ethernet  HWaddr D8:58:D7:00:02:DE
          inet addr:89.102.175.10  Bcast:89.102.175.255  Mask:255.255.255.0
          inet6 addr: fe80::da58:d7ff:fe00:2de/64 Scope:Link
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:648 errors:0 dropped:0 overruns:0 frame:0
          TX packets:346 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000
          RX bytes:194087 (189.5 KiB)  TX bytes:35119 (34.2 KiB)
          Base address:0xe000

lo        Link encap:Local Loopback
          inet addr:127.0.0.1  Mask:255.0.0.0
          inet6 addr: ::1/128 Scope:Host
          UP LOOPBACK RUNNING  MTU:65536  Metric:1
          RX packets:104 errors:0 dropped:0 overruns:0 frame:0
          TX packets:104 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:0
          RX bytes:8610 (8.4 KiB)  TX bytes:8610 (8.4 KiB)

teql0     Link encap:UNSPEC  HWaddr 00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00
          NOARP  MTU:1500  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:0 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:100
          RX bytes:0 (0.0 B)  TX bytes:0 (0.0 B)

wlan0     Link encap:Ethernet  HWaddr 60:02:B4:7D:85:CD
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:474 errors:0 dropped:0 overruns:0 frame:0
          TX packets:393 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000
          RX bytes:48015 (46.8 KiB)  TX bytes:163832 (159.9 KiB)
```

Compared to the cheap routers there is much more disk space:

```console
root@turris:~# df -h
Filesystem                Size      Used Available Use% Mounted on
rootfs                  249.0M     31.6M    217.4M  13% /
/dev/root               249.0M     31.6M    217.4M  13% /
tmpfs                  1013.9M    312.0K   1013.6M   0% /tmp
tmpfs                   512.0K      4.0K    508.0K   1% /dev
```

The same applies to the memory used by applications:

```console
root@turris:~# free
             total         used         free       shared      buffers
Mem:       2076428        67700      2008728            0            0
-/+ buffers:              67700      2008728
Swap:            0            0            0
```

A two-core processor can be handy as well:

```console
root@turris:~# cat /proc/cpuinfo
processor       : 0
cpu             : e500v2
clock           : 1200.000000MHz
revision        : 5.1 (pvr 8021 1051)
bogomips        : 150.00

processor       : 1
cpu             : e500v2
clock           : 1200.000000MHz
revision        : 5.1 (pvr 8021 1051)
bogomips        : 150.00

total bogomips  : 300.00
timebase        : 75000000
platform        : P2020 RDB
model           : Turris
Memory          : 2048 MB
```

The rest of the commands can be seen in my GitHub
[repository](https://github.com/ruzickap/linux.xvx.cz/tree/gh-pages/files/turris).
On the same page you can see the "original" `/etc` directory compressed right
after I finished the "connection wizard".

Next pictures are showing the original package, t-shirt, invoice, etc:

![Turris package contents with t-shirt](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165933.jpg)

![Turris shipping box](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-163632.jpg)

![Turris package opening](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-164952.jpg)

![Turris router in packaging](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165004.jpg)

![Turris router unboxing](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165039.jpg)

![Turris router with accessories](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165102.jpg)

![Turris router antennas](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165112.jpg)

![Turris router power adapter](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165137.jpg)

![Turris router enclosure detail](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165159.jpg)

![Turris router side view](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165233.jpg)

![Turris router top view](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165257.jpg)

![Turris router bottom view](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165316.jpg)

![Turris router label and specifications](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165339.jpg)

![Turris router ports closeup](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165418.jpg)

![Turris router LED indicators](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165505.jpg)

![Turris router assembled front view](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165738.jpg)

![Turris router assembled back view](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-170025.jpg)

![Turris router with antennas attached](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-170053.jpg)

![Turris router running](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-170202.jpg)

![Turris setup wizard screenshot 1](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140401-170528.jpg)

![Turris setup wizard screenshot 2](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140401-170627.jpg)

![Turris web interface screenshot 1](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140412-153358.jpg)

![Turris web interface screenshot 2](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140412-153428.jpg)

![Turris web interface screenshot 3](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140412-153456.jpg)

Next time I'll describe the additional OpenWrt configuration which I did to make
the router work better.
