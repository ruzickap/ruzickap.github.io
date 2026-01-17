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
License](https://www.ohwr.org/projects/cernohl/wiki) and can be found here:
[https://www.turris.cz/en/hardware-documentation](https://www.turris.cz/en/hardware-documentation).
These details are really nice, because everybody can look at it and improve...

Here are some pictures of how the router looks:

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165738.jpg)

The well-designed metal box looks much better than any cheap routers I worked
with before.

Another photo showing it from the back side:

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-170025.jpg)

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

Compared to the cheap routers there is much more disk space:

The same applies to the memory used by applications:

A two-core processor can be handy as well:

The rest of the commands can be seen in my GitHub
[repository](https://github.com/ruzickap/linux.xvx.cz/tree/gh-pages/files/turris).
On the same page you can see the "original" /etc directory compressed right
after I finished the "connection wizard".

Next pictures are showing the original package, t-shirt, invoice, etc:

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165933.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-163632.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-164952.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165004.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165039.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165102.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165112.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165137.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165159.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165233.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165257.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165316.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165339.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165418.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165505.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-165738.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-170025.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-170053.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140331-170202.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140401-170528.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140401-170627.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140412-153358.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140412-153428.jpg)

![image](https://github.com/ruzickap/linux.xvx.cz/raw/gh-pages/pics/turris/20140412-153456.jpg)

Next time I'll describe the additional OpenWrt configuration which I did to make
the router work better.
