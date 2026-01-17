---
title: OpenWrt (Backfire 10.03) and TL-WR1043ND
author: Petr Ruzicka
date: 2011-12-13
description: ""
categories: [Linux, OpenWrt]
tags: [TP-Link, WiFi, USB, Dnsmasq, webcam]
---

> <https://linux-old.xvx.cz/2011/12/openwrt-backfire-10-03-and-tl-wr1043nd/>
{: .prompt-info }

I forgot to publish this article almost a year ago :-( So now it's a good time
before I'll write another one...

It's **OUTDATED** and **INCOMPLETE**, but it can still bring some light...

---

Few days ago I bought WiFi router [TP-Link TL-WR1043ND](https://openwrt.org/toh/tp-link/tl-wr1043nd).
The main reason was the USB, Gigabit Ethernet ports, 802.11n and
[support](https://dev.openwrt.org/milestone/Backfire%2010.03) in latest
[OpenWrt](https://openwrt.org/).

OpenWrt is amazing project which can create really powerful device from the wifi
routers.

I spent many days with collecting various information about OpenWrt, because I
want to use web camera, USB hub, external USB storage and later few
thermometers.

I decided to compile it from scratch (using Fedora 13), because squashfs can't
work with block-extroot without building an image (see
[https://forum.openwrt.org/viewtopic.php?pid=108642](https://forum.openwrt.org/viewtopic.php?pid=108642)).
I prefer to use [squashfs](https://squashfs.sourceforge.net/), because some
people say it's better than jffs2.

Here you can find my notes...

Download necessary packages to compile OpenWrt:

```bash
yum install subversion gcc-c++ libz-dev flex unzip ncurses-devel zlib-devel
```

Download OpenWrt Backfire from svn:

```bash
cd /var/tmp/ || exit
svn co svn://svn.openwrt.org/openwrt/branches/backfire
```

or use the standard way:

```bash
cd /var/tmp/ || exit
wget http://downloads.openwrt.org/backfire/10.03/backfire_10.03_source.tar.bz2
tar xvjf backfire_10.03_source.tar.bz2
mv backfire_10.03 backfire
```

Start configuring it:

```bash
cd backfire/ || exit
./scripts/feeds update
./scripts/feeds install xxx
make menuconfig
```

Select following items in the menuconfig and the items from the command below:

```text
Target System (Atheros AR71xx/AR7240/AR913x)
Target Profile (TP-LINK TL-WR1043ND v1)
Kernel modules ---> Filesystems ---> kmod-fs-ext2
Kernel modules ---> USB Support ---> kmod-usb-core
Kernel modules ---> USB Support ---> kmod-usb-storage
Kernel modules ---> USB Support ---> kmod-usb-video
Kernel modules ---> USB Support ---> kmod-usb-serial
Kernel modules ---> USB Support ---> kmod-usb-serial-pl2303
Kernel modules ---> Video Support ---> kmod-video-core
Kernel modules ---> Video Support ---> kmod-video-uvc
Utilities ---> disc ---> block-extroot
#Base system ---> block-extroot

and all the packages you installed before
```

Run `make V=99` to compile it.

I'll put all the root files to the USB disk and I formatted my 500MB USB stick
this way:

```console
root@fedora:/# parted -s /dev/sda p
Model: Generic STORAGE DEVICE (scsi)
Disk /dev/sda: 492MB
Sector size (logical/physical): 512B/512B
Partition Table: msdos

Number Start End Size Type File system Flags
1 16.4kB 450MB 450MB primary ext2
2 450MB 492MB 41.9MB primary linux-swap(v1)
```

Connect router to your desktop/laptop and flash it form the webgui using this
file: `openwrt-ar71xx-tl-wr1043nd-v1-squashfs-factory.bin` or use these commands
if you already have OpenWrt installed:

```bash
scp ./backfire/bin/ar71xx/openwrt-ar71xx-tl-wr1043nd-v1-squashfs-sysupgrade.bin root@192.168.0.2:/tmp
sysupgrade openwrt-ar71xx-tl-wr1043nd-v1-squashfs-sysupgrade.bin
#scp ./backfire/bin/ar71xx/openwrt-ar71xx-tl-wr1043nd-v1-squashfs-sysupgrade.bin root@192.168.0.2:/tmp
#mtd -e firmware -r write /tmp/openwrt-ar71xx-tl-wr1043nd-v1-squashfs-sysupgrade.bin firmware
```

Set your password using telnet command and setup up `block-extroot` ([Rootfs on
External Storage](https://openwrt.org/docs/guide-user/additional-software/extroot_configuration))
and use my USB stick as root partition to have more space:

```bash
ifconfig eth0 192.168.1.2 netmask 255.255.255.0
telnet 192.168.1.1

uci set fstab.@mount[0].fstype=ext2
uci set fstab.@mount[0].device=/dev/sda1
uci set fstab.@mount[0].is_rootfs=1
uci set fstab.@mount[0].enabled_fsck=1
uci set fstab.@mount[0].target=/mnt
uci set fstab.@mount[0].enabled=1
uci commit fstab

passwd
reboot
```

Turn on the swap:

```bash
uci set fstab.@swap[0].device=/dev/sda2
uci set fstab.@swap[0].enabled=1
```

Add option `force_space` in `/etc/opkg.conf` to allow installation of packets
bigger than your `/rom` partitions free space:

```bash
echo option force_space >> /etc/opkg.conf
```

Setup the ssh key to enable autologin:

```bash
scp "$HOME/.ssh/id_rsa.pub" root@192.168.0.2:/tmp/authorized_keys
ssh root@192.168.0.2
cp /tmp/authorized_keys /etc/dropbear/authorized_keys
chmod 600 /etc/dropbear/authorized_keys
```

Configure getting DHCP requests from WAN (Internet) port, wifi and firewall:

```bash
uci set network.lan.ipaddr=192.168.0.193
uci set network.lan.netmask=255.255.255.192

uci set network.wan.ifname=eth0.2
uci set network.wan.proto=static
uci set network.wan.type=bridge
uci set network.wan.ipaddr=192.168.0.2
uci set network.wan.netmask=255.255.255.192
uci set network.wan.dns="192.168.0.1 8.8.8.8"
uci set network.wan.gateway=192.168.0.1

uci set network.wifi_open=interface
uci set network.wifi_open.ifname=eth0.3
uci set network.wifi_open.type=bridge
uci set network.wifi_open.proto=static
uci set network.wifi_open.ipaddr=192.168.0.129
uci set network.wifi_open.netmask=255.255.255.192

uci set network.wifi_priv=interface
uci set network.wifi_priv.ifname=eth0.1
uci set network.wifi_priv.type=bridge
uci set network.wifi_priv.proto=static
uci set network.wifi_priv.ipaddr=192.168.0.65
uci set network.wifi_priv.netmask=255.255.255.192

uci add network switch_vlan
uci set network.@switch_vlan[-1].device=rtl8366rb
uci set network.@switch_vlan[-1].vlan=3
uci set network.@switch_vlan[-1].ports=5

uci set wireless.@wifi-iface[0].ssid=test123
uci set wireless.@wifi-iface[0].network=wifi_open
uci set wireless.@wifi-iface[0].encryption=psk2
uci set wireless.@wifi-iface[0].key=yyyyyyyy
uci set wireless.@wifi-iface[0].isolate=1

uci add wireless wifi-iface
uci set wireless.@wifi-iface[-1].device=radio0
uci set wireless.@wifi-iface[-1].network=wifi_priv
uci set wireless.@wifi-iface[-1].mode=ap
uci set wireless.@wifi-iface[-1].ssid=test345
uci set wireless.@wifi-iface[-1].encryption=psk2
uci set wireless.@wifi-iface[-1].key=yyyyyyyy

uci set wireless.radio0.channel=8
uci set wireless.radio0.country=CZ
uci set wireless.radio0.hwmode=11ng
uci del wireless.@wifi-device[0].disabled

uci set firewall.@zone[1].conntrack=1
uci set firewall.@zone[1].forward=ACCEPT
uci set firewall.@zone[1].input=ACCEPT

uci add firewall zone
uci set firewall.@zone[-1].name=wifi_open
uci set firewall.@zone[-1].input=REJECT
uci set firewall.@zone[-1].output=ACCEPT
uci set firewall.@zone[-1].forward=REJECT
uci set firewall.@zone[-1].conntrack=1

uci add firewall zone
uci set firewall.@zone[-1].name=wifi_priv
uci set firewall.@zone[-1].input=ACCEPT
uci set firewall.@zone[-1].output=ACCEPT
uci set firewall.@zone[-1].forward=REJECT

uci add firewall forwarding
uci set firewall.@forwarding[-1].src=wifi_open
uci set firewall.@forwarding[-1].dst=wan

uci add firewall forwarding
uci set firewall.@forwarding[-1].src=wifi_priv
uci set firewall.@forwarding[-1].dst=wan

uci add firewall rule
uci set firewall.@rule[-1].name=icmp-echo-request
uci set firewall.@rule[-1].src=wifi_open
uci set firewall.@rule[-1].target=ACCEPT
uci set firewall.@rule[-1].proto=icmp
uci set firewall.@rule[-1].icmp_type=echo-request

uci add firewall rule
uci set firewall.@rule[-1].name=dhcp
uci set firewall.@rule[-1].src=wifi_open
uci set firewall.@rule[-1].target=ACCEPT
uci set firewall.@rule[-1].proto=udp
uci set firewall.@rule[-1].src_port=68

uci set dhcp.@dnsmasq[0].domain=xvx.cz
uci set dhcp.@dnsmasq[0].port=0
uci set dhcp.@dnsmasq[0].cachelocal=0
uci set dhcp.@dnsmasq[0].dhcpscript=/etc/dnsmasq.script

uci set dhcp.wifi_open=dhcp
uci set dhcp.wifi_open.interface=wifi_open
uci set dhcp.wifi_open.start=130
uci set dhcp.wifi_open.limit=60
uci set dhcp.wifi_open.dhcp_option=6,192.168.0.1

uci set dhcp.wifi_priv=dhcp
uci set dhcp.wifi_priv.interface=wifi_priv
uci set dhcp.wifi_priv.start=70
uci set dhcp.wifi_priv.limit=60
uci set dhcp.wifi_priv.dhcp_option=6,192.168.0.1

uci set dhcp.lan.start=194
uci set dhcp.lan.limit=60
uci set dhcp.lan.dhcp_option=6,192.168.0.1

uci add dhcp host
uci set dhcp.@host[-1].name=peru-nb-work
uci set dhcp.@host[-1].ip=192.168.0.66
uci set dhcp.@host[-1].mac=00:1C:65:38:7C:F6

uci add dhcp host
uci set dhcp.@host[-1].name=peru-nb
uci set dhcp.@host[-1].ip=192.168.0.67
uci set dhcp.@host[-1].mac=00:15:00:11:48:5a

uci add dhcp host
uci set dhcp.@host[-1].name=phone
uci set dhcp.@host[-1].ip=192.168.0.68
uci set dhcp.@host[-1].mac=00:23:76:d6:42:c7

uci add dhcp host
uci set dhcp.@host[-1].name=palm
uci set dhcp.@host[-1].ip=192.168.0.69
uci set dhcp.@host[-1].mac=00:0b:6c:57:da:9a

wget http://rpc.one.pl/pliki/openwrt/backfire/10.03.x/dnsmasq/dnsmasq -O /etc/init.d/dnsmasq
```

Set the hostname, timezone and configure syslogd:

```bash
uci set system.@system[0].timezone=CET-1CEST,M3.5.0,M10.5.0/3
uci set system.@system[0].timezone=CET-1CEST,M3.5.0,M10.5.0/3
uci set system.@system[0].log_size=64
uci set system.@system[0].log_ip=192.168.0.1
```

Configure certificate details for https:

```bash
uci set uhttpd.px5g.days=3650
uci set uhttpd.px5g.country=CZ
uci set uhttpd.px5g.state="Czech Republic"
uci set uhttpd.px5g.location=Brno
rm /etc/uhttpd.crt /etc/uhttpd.key
```

Configure darkstat, snmpd and vnstat.

```bash
uci set darkstat.@darkstat[0].interface=wan

uci set mini_snmpd.@mini_snmpd[0].interfaces=lo,br-wan,br-wifi_open,br-wifi_private
uci set mini_snmpd.@mini_snmpd[0].community=OpenWrt
uci set mini_snmpd.@mini_snmpd[0].location='V Ujezdech 1, Brno'
uci set mini_snmpd.@mini_snmpd[0].contact='PeRu'
```

Few more commands to configure "non-uci" files:

```bash
sed -i 's/\(^mailhub\).*/\1=gate.xvx.cz/;s/\(^rewriteDomain=\).*/\1xvx.cz/' /etc/ssmtp/ssmtp.conf

sed -i 's/\(^GatewayInterface\).*/\1 br-wifi_open/;s/^# \(GatewayName\).*/\1 Medlanky/;s/^\([[:space:]]*FirewallRule allow tcp port 80\)/#\1/;s/\(.*FirewallRule allow tcp port 22\)/#\1/;s/\(.*FirewallRule allow tcp port 443\)/#\1/;/^FirewallRuleSet authenticated-users/a\ FirewallRule allow' /etc/nodogsplash/nodogsplash.conf

sed -i 's@\(\)@\1\n
<h3>For Internet access - click the dog</h3>
\n
<h3>Pro pristup na Internet klikni na psa.</h3>
@' /etc/nodogsplash/htdocs/splash.html

cat > /etc/dnsmasq.script << \EOF #!/bin/sh /bin/echo `/bin/date +"%F %T"` $* >> /tmp/dnsmasq.script.log

case $1 in
"add")
#grep -q $2 /etc/config/dhcp || /usr/bin/nmap -T4 -A $3 | ssmtp petr.ruzicka@gmail.com
#echo "Subject: New connection to `hostname` ($2 $3)\n\n`/usr/bin/nmap -T4 -A $3`" | ssmtp petr.ruzicka@gmail.com
echo "ADD: MAC: $MAC; DNSMASQ_LEASE_LENGTH: $DNSMASQ_LEASE_LENGTH; DNSMASQ_LEASE_EXPIRES: $DNSMASQ_LEASE_EXPIRES; DNSMASQ_TIME_REMAINING: $DNSMASQ_TIME_REMAINING; DNSMASQ_TAGS: $DNSMASQ_TAGS" >> /tmp/dnsmasq.script.log
;;
"old")
echo "OLD: MAC: $MAC; DNSMASQ_LEASE_LENGTH: $DNSMASQ_LEASE_LENGTH; DNSMASQ_LEASE_EXPIRES: $DNSMASQ_LEASE_EXPIRES; DNSMASQ_TIME_REMAINING: $DNSMASQ_TIME_REMAINING; DNSMASQ_TAGS: $DNSMASQ_TAGS" >> /tmp/dnsmasq.script.log
;;
"del")
echo "DEL: MAC: $MAC; DNSMASQ_LEASE_LENGTH: $DNSMASQ_LEASE_LENGTH; DNSMASQ_LEASE_EXPIRES: $DNSMASQ_LEASE_EXPIRES; DNSMASQ_TIME_REMAINING: $DNSMASQ_TIME_REMAINING; DNSMASQ_TAGS: $DNSMASQ_TAGS" >> /tmp/dnsmasq.script.log
;;
esac
EOF

chmod a+x /etc/dnsmasq.script

cat >> /etc/digitemp.script << \EOF
#!/bin/sh /usr/bin/digitemp_DS9097 -c/etc/digitemp.conf -a -n0 -d10 -q -s/dev/ttyUSB0 -o"PUTVAL OpenWrt/temp/temperature-%s interval=10 %N:%.2C"
EOF
chmod a+x /etc/digitemp.script
mkdir /root/.ssh/
dropbearkey -t rsa -f /root/.ssh/id_rsa

# Save the public key to the ~/.ssh/authorized_keys on the server cat > /etc/fswebcam.script << \EOF
#!/bin/sh
OUTPUT_FILE="/tmp/webcam/$(date +%F_%H-%M).png"
OUTPUT_DIR=$(dirname "$OUTPUT_FILE")

date > /tmp/fswebcam.script.log

if [ "$(pgrep -f fswebcam | wc -l)" -ge 4 ]; then
  BAD_STATE=1
  # shellcheck disable=SC2009 # ps | grep is intentional to show full process details for debugging
  echo -e "*** fswebcam already running [$(pgrep -f fswebcam | wc -l)] !!!\n*** ps -ef | grep -E '(fswebcam|scp)':\n$(ps -ef | grep -E '(fswebcam|scp)')\n*** killall fswebcam:\n$(killall fswebcam)\n" | tee -a /tmp/fswebcam.script.log
fi

test -d "$OUTPUT_DIR" || mkdir -p "$OUTPUT_DIR"

fswebcam --no-banner --rotate 180 --resolution 640x480 --fps 15 --png 7 --save "$OUTPUT_FILE" 2>&1 | tee -a /tmp/fswebcam.script.log

if scp -B -p -i /root/.ssh/id_rsa "$OUTPUT_FILE" ruzickap@gate.xvx.cz:/home/ftp/ >> /tmp/fswebcam.script.log 2>&1; then
  rm "$OUTPUT_FILE"
else
  BAD_STATE=1
  test -d /root/webcam_medlanky || mkdir -p /root/webcam_medlanky
  mv "$OUTPUT_FILE" /root/webcam_medlanky/
  echo -e "*** ls -la /root/webcam_medlanky/:\n$(ls -la /root/webcam_medlanky/)\n" | tee -a /tmp/fswebcam.script.log
fi

if [ "$BAD_STATE" -eq 1 ]; then
  echo -e "Subject: Webcam script failed!\n\n$(cat /tmp/fswebcam.script.log)\n" | ssmtp petr.ruzicka@gmail.com
fi
EOF

chmod a+x /etc/fswebcam.script
echo "*/30 * * * * /etc/fswebcam.script" >> /etc/crontabs/root
/etc/init.d/cron enable
/etc/init.d/cron start
```

Collectd configuration:

```bash
/usr/bin/digitemp_DS9097 -a -i -c /etc/digitemp.conf -s/dev/ttyUSB0

mkdir -p /etc/collectd/conf.d
cat >> /etc/collectd/conf.d/my_collectd.conf << \EOF
LoadPlugin contextswitch
LoadPlugin memory
LoadPlugin uptime
LoadPlugin vmem
LoadPlugin users

LoadPlugin protocols
Value "/^Tcp:/"
IgnoreSelected false

LoadPlugin syslog
LogLevel "info"
EOF

uci set luci_statistics.collectd_ping.enable=1
uci set luci_statistics.collectd_ping.Hosts=www.google.com
uci set luci_statistics.collectd_df.enable=1
uci set luci_statistics.collectd_df.Devices=/dev/sda1
uci set luci_statistics.collectd_df.MountPoints=/mnt/sda1
uci set luci_statistics.collectd_df.FSTypes=fuseblk
uci set luci_statistics.collectd_disk.enable=1
uci set luci_statistics.collectd_disk.Disks=sda
uci set luci_statistics.collectd_dns.enable=1
uci set luci_statistics.collectd_dns.Interfaces="br-wan br-wifi_open br-wifi_private"
uci set luci_statistics.collectd_interface.Interfaces="br-wan br-wifi_open br-wifi_private"
uci set luci_statistics.collectd_irq.enable=1
uci set luci_statistics.collectd_netlink.enable=1
uci set luci_statistics.collectd_netlink.VerboseInterfaces="br-wan br-wifi_open br-wifi_private"
uci set luci_statistics.collectd_netlink.QDisc="br-wan br-wifi_open br-wifi_private"
uci set luci_statistics.collectd_network.enable=1
uci set luci_statistics.@collectd_network_server[0].host="\"collectd.xvx.cz\""
uci set luci_statistics.collectd_tcpconns.LocalPorts="22 80 443 667"
uci set luci_statistics.@collectd_exec_input[0].cmdline="/etc/digitemp.script"

/etc/init.d/luci_statistics enable
```

Useful commands:

```bash
swconfig dev rtl8366rb show
swconfig dev rtl8366rb vlan 1 show
cat /proc/net/vlan/config
snmpwalk -v2c -c public_wifi 192.168.0.2
logread
```

Serial Port Temperature Sensors:
[https://web.archive.org/web/2020/http://www.linuxfocus.org/English/November2003/article315.shtml](https://web.archive.org/web/2020/http://www.linuxfocus.org/English/November2003/article315.shtml)
[https://martybugs.net/electronics/tempsensor/hardware.cgi](https://martybugs.net/electronics/tempsensor/hardware.cgi)

Serial cable:
[https://halfface.se/wiki/index.php/Openwrt](https://halfface.se/wiki/index.php/Openwrt)
