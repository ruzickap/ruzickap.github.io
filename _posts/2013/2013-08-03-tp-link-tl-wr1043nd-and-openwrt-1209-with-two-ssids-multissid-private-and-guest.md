---
title: TP-Link TL-WR1043ND and OpenWrt 12.09 with two SSIDs (MultiSSID) - private and guest
author: Petr Ruzicka
date: 2013-08-03
description: TP-Link TL-WR1043ND and OpenWrt 12.09 with two SSIDs (MultiSSID) - private and guest
categories: [OpenWrt]
tags: [wifi, wi-fi, Transmission, torrent, tftp, TL-WR1043ND, dhcp]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2013/08/tp-link-tl-wr1043nd-and-openwrt-1209.html)
{: .prompt-info }

I decided to change my home network to match the following "network diagram":

![OpenWrt multi-SSID network diagram](https://raw.githubusercontent.com/ruzickap/linux.xvx.cz/refs/heads/gh-pages/pics/openwrt/wifi_openwrt2.svg)

The core part of the design is [TP-Link
TL-WR1043ND](https://www.tp-link.com/en/products/details/?model=TL-WR1043ND) wifi
router running [OpenWrt](https://openwrt.org/) with a small 16GB USB stick
[/dev/sda1] containing ext3 partition with OpenWrt configuration + swap.

There is also a 16GB USB stick and 2 thermometers connected using USB Serial
connector (bought on eBay):

I'm going to use the last stable version of the OpenWrt firmware:
[openwrt-ar71xx-generic-tl-wr1043nd-v1-squashfs-sysupgrade.bin](https://downloads.openwrt.org/attitude_adjustment/12.09/ar71xx/generic/openwrt-ar71xx-generic-tl-wr1043nd-v1-squashfs-sysupgrade.bin)

Upgrade the firmware and remove the old configuration:

```bash
rm -r /tmp/opkg-lists/
sysctl -w vm.drop_caches=1
sysupgrade -v -n https://downloads.openwrt.org/attitude_adjustment/12.09/ar71xx/generic/openwrt-ar71xx-generic-tl-wr1043nd-v1-squashfs-sysupgrade.bin
```

Here are the notes how way how I configured it.

If you don't like the commands feel free to check the configs here:
[https://github.com/ruzickap/linux.xvx.cz/tree/gh-pages/files/openwrt](https://github.com/ruzickap/linux.xvx.cz/tree/gh-pages/files/openwrt)

Configure the system, ssh on port 2222 and LAN + wifi IP:

```bash
telnet 192.168.1.1
passwd

#Erase ALL
#rm -r /overlay/*
#mtd -r erase rootfs_data

opkg update
opkg install block-mount kmod-fs-ext4 kmod-usb-storage

uci set system.@system[0].hostname=gate
uci set system.@system[0].timezone=CET-1CEST,M3.5.0,M10.5.0/3
uci set system.@system[0].timezone=CET-1CEST,M3.5.0,M10.5.0/3
uci set system.@system[0].log_file=/etc/messages
uci set system.@system[0].log_size=1024
uci set system.@system[0].log_type=file

uci set dropbear.@dropbear[0].Port=2222
uci set system.@timeserver[0].enable_server=1

uci add firewall rule
uci set firewall.@rule[-1].name=ssh
uci set firewall.@rule[-1].src=wan
uci set firewall.@rule[-1].target=ACCEPT
uci set firewall.@rule[-1].proto=tcp
uci set firewall.@rule[-1].dest_port=2222

uci add firewall redirect
uci set firewall.@redirect[-1].name=ssh_lan
uci set firewall.@redirect[-1].src=lan
uci set firewall.@redirect[-1].proto=tcp
uci set firewall.@redirect[-1].src_dport=22
uci set firewall.@redirect[-1].dest_port=2222
uci set firewall.@redirect[-1].dest_ip=192.168.0.1

uci set network.lan.ipaddr=192.168.0.1
uci set network.lan.netmask=255.255.255.0

uci set dhcp.lan.start=200
uci set dhcp.lan.limit=54

uci set dhcp.@dnsmasq[0].domain=xvx.cz
uci set dhcp.@dnsmasq[0].leasefile=/etc/dnsmasq-dhcp.leases
uci set dhcp.@dnsmasq[0].port=0
uci set dhcp.@dnsmasq[0].cachelocal=0
uci set dhcp.lan.dhcp_option=6,8.8.8.8
uci set dhcp.wifi_open.dhcp_option=6,8.8.8.8

uci add fstab mount
uci set fstab.@mount[-1].device=/dev/sda1
uci set fstab.@mount[-1].fstype=ext3
uci set fstab.@mount[-1].options=rw,sync,noatime,nodiratime
uci set fstab.@mount[-1].enabled=1
uci set fstab.@mount[-1].enabled_fsck=0
uci set fstab.@mount[-1].is_rootfs=1

uci set fstab.@swap[0].enabled=1
```

Configure the private wifi:

```bash
uci add wireless wifi-iface
uci set wireless.@wifi-iface[-1].device=radio0
uci set wireless.@wifi-iface[-1].network=lan
uci set wireless.@wifi-iface[-1].mode=ap
uci set wireless.@wifi-iface[-1].ssid=peru_private
uci set wireless.@wifi-iface[-1].encryption=psk2+tkip+aes
uci set wireless.@wifi-iface[-1].key=xxxxxxxx

uci set wireless.radio0.channel=8
uci set wireless.radio0.country=CZ
uci set wireless.radio0.htmode=HT40-
uci set wireless.radio0.noscan=1
uci set wireless.radio0.bursting=1
uci set wireless.radio0.ff=1
uci set wireless.radio0.compression=1
uci set wireless.radio0.xr=1
uci set wireless.radio0.ar=1
uci set wireless.radio0.txpower=20
uci del wireless.@wifi-device[0].disabled
```

Configure the wifi_open - guest wifi access. For some reason
[OpenWrt Guest WLAN](https://web.archive.org/web/20140825150515/http://wiki.openwrt.org/doc/recipes/guest-wlan)
is not working for me. I found this article (Polish)
[https://eko.one.pl/forum/viewtopic.php?id=2937](https://eko.one.pl/forum/viewtopic.php?id=2937)
how to do it.

```bash
#Use your default MAC + 1 - my router's original MAC is 94:0C:6D:AC:55:AC
MAC="96:0C:6D:AC:55:AD"

uci set network.wifi_open=interface
uci set network.wifi_open.ifname=eth0.3
uci set network.wifi_open.type=bridge
uci set network.wifi_open.macaddr=$MAC
uci set network.wifi_open.proto=static
uci set network.wifi_open.ipaddr=10.0.0.1
uci set network.wifi_open.netmask=255.255.255.0

uci set wireless.@wifi-iface[0].ssid=medlanky.xvx.cz
uci set wireless.@wifi-iface[0].network=wifi_open
uci set wireless.@wifi-iface[0].encryption=none
uci set wireless.@wifi-iface[0].isolate=1
uci set wireless.@wifi-iface[0].macaddr=$MAC

uci add firewall zone
uci set firewall.@zone[-1].name=wifi_open
uci set firewall.@zone[-1].input=REJECT
uci set firewall.@zone[-1].output=ACCEPT
uci set firewall.@zone[-1].forward=REJECT

uci add firewall forwarding
uci set firewall.@forwarding[-1].src=wifi_open
uci set firewall.@forwarding[-1].dest=wan

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
uci set firewall.@rule[-1].src_port=67-68
uci set firewall.@rule[-1].dest_port=67-68

uci add firewall rule
uci set firewall.@rule[-1].name=dns
uci set firewall.@rule[-1].src=wifi_open
uci set firewall.@rule[-1].target=ACCEPT
uci set firewall.@rule[-1].proto=tcpudp
uci set firewall.@rule[-1].dest_port=53

uci set dhcp.wifi_open=dhcp
uci set dhcp.wifi_open.interface=wifi_open
uci set dhcp.wifi_open.start=2
uci set dhcp.wifi_open.limit=253
uci set dhcp.wifi_open.dhcp_option=6,8.8.8.8
uci set dhcp.wifi_open.leasetime=1h

uci commit dhcp
sed -i "/dnsmasq-dhcp.leases/a list 'interface' 'lan'" /etc/config/dhcp
sed -i "/dnsmasq-dhcp.leases/a list 'interface' 'wifi_open'" /etc/config/dhcp

rm /etc/resolv.conf
cat > /etc/resolv.conf << EOF
search xvx.cz
nameserver 8.8.8.8
EOF
```

Define the DHCP static hosts:

```bash
# WiFi
uci add dhcp host
uci set dhcp.@host[-1].name=peru-nb-work-wifi
uci set dhcp.@host[-1].ip=192.168.0.2
uci set dhcp.@host[-1].mac=00:26:c6:51:39:34

uci add dhcp host
uci set dhcp.@host[-1].name=andy-nb-wifi
uci set dhcp.@host[-1].ip=192.168.0.3
uci set dhcp.@host[-1].mac=74:f0:6d:93:c7:3a

uci add dhcp host
uci set dhcp.@host[-1].name=peru-nb-old-wifi
uci set dhcp.@host[-1].ip=192.168.0.4
uci set dhcp.@host[-1].mac=00:15:00:11:48:5A

uci add dhcp host
uci set dhcp.@host[-1].name=andy-android-wifi
uci set dhcp.@host[-1].ip=192.168.0.5
uci set dhcp.@host[-1].mac=00:23:76:D6:42:C7

uci add dhcp host
uci set dhcp.@host[-1].name=peru-android-work-wifi
uci set dhcp.@host[-1].ip=192.168.0.6
uci set dhcp.@host[-1].mac=00:90:4c:c5:00:34

uci add dhcp host
uci set dhcp.@host[-1].name=peru-palm-wifi
uci set dhcp.@host[-1].ip=192.168.0.7
uci set dhcp.@host[-1].mac=00:0b:6c:57:da:9a

uci add dhcp host
uci set dhcp.@host[-1].name=RTL8187-wifi
uci set dhcp.@host[-1].ip=192.168.0.8
uci set dhcp.@host[-1].mac=00:C0:CA:54:F5:BA

# NIC
uci add dhcp host
uci set dhcp.@host[-1].name=peru-nb-work-nic
uci set dhcp.@host[-1].ip=192.168.0.130
uci set dhcp.@host[-1].mac=00:22:68:1a:14:5d

uci add dhcp host
uci set dhcp.@host[-1].name=andy-nb-nic
uci set dhcp.@host[-1].ip=192.168.0.131
uci set dhcp.@host[-1].mac=20:cf:30:31:da:b3

uci add dhcp host
uci set dhcp.@host[-1].name=peru-nb-old-nic
uci set dhcp.@host[-1].ip=192.168.0.132
uci set dhcp.@host[-1].mac=00:13:D4:D1:03:57

uci add dhcp host
uci set dhcp.@host[-1].name=peru-tv-nic
uci set dhcp.@host[-1].ip=192.168.0.133
uci set dhcp.@host[-1].mac=00:12:FB:94:1B:9A

uci add dhcp host
uci set dhcp.@host[-1].name=raspberrypi-nic
uci set dhcp.@host[-1].ip=192.168.0.134
uci set dhcp.@host[-1].mac=b8:27:eb:8c:97:9e

uci add dhcp host
uci set dhcp.@host[-1].name=server-nic
uci set dhcp.@host[-1].ip=192.168.0.135
uci set dhcp.@host[-1].mac=00:1f:c6:e9:f5:14
```

Configure the ssh to enable autologin:

```bash
scp $HOME/.ssh/id_rsa.pub root@192.168.1.1:/tmp/authorized_keys
ssh root@192.168.1.1
cp /tmp/authorized_keys /etc/dropbear/authorized_keys
chmod 600 /etc/dropbear/authorized_keys
uci set dropbear.@dropbear[0].RootPasswordAuth=off

uci commit
reboot
```

Repeat the steps above to save all the changes/files to the external USB
storage.

Install the following packages:

```bash
opkg update
opkg install bind-dig bzip2 collectd-mod-conntrack collectd-mod-cpu collectd-mod-df collectd-mod-disk collectd-mod-dns collectd-mod-exec collectd-mod-irq collectd-mod-memory collectd-mod-ping collectd-mod-processes collectd-mod-syslog collectd-mod-tcpconns ddns-scripts digitemp ethtool file gzip htop kmod-usb-serial-pl2303 less lftp lighttpd-mod-cgi lighttpd-mod-proxy lsof luci-app-statistics luci-app-transmission luci-app-upnp luci-app-vnstat luci-app-wol luci-app-qos luci-app-ddns luci-app-firewall
opkg install luci-app-watchcat mc mtr nmap nodogsplash openssh-sftp-server openssl-util rsync screen shadow-useradd ssmtp sudo sysstat tcpdump transmission-remote transmission-web vnstati wget zoneinfo-europe
```

Add my user and configure mc, screen and shell:

```bash
mkdir -p /usr/lib/mc/extfs.d
touch /etc/mc/sfs.ini

wget --no-check-certificate https://raw.github.com/MidnightCommander/mc/master/misc/filehighlight.ini -O /etc/mc/filehighlight.ini

mkdir -p /etc/skel/.mc/
chmod 700 /etc/skel/.mc
cat > /etc/skel/.mc/ini << EOF
[Midnight-Commander]
auto_save_setup=0
drop_menus=1
use_internal_edit=1
confirm_exit=0

[Layout]
menubar_visible=0
message_visible=0
EOF
cp -r /etc/skel/.mc /root/

wget --no-check-certificate https://raw.github.com/MidnightCommander/mc/master/contrib/mc-wrapper.sh.in -O - | sed 's|@bindir@/mc|/usr/bin/mc --nomouse|' > /usr/bin/mc-wrapper.sh
chmod a+x /usr/bin/mc-wrapper.sh

echo "ruzickap  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

cat >> /etc/screenrc << EOF
defscrollback 1000
startup_message off
termcapinfo xterm ti@:te@
hardstatus alwayslastline '%{= kG}[ %{G}%H %{g}][%= %{= kw}%?%-Lw%?%{r}(%{W}%n*%f%t%?(%u)%?%{r})%{w}%?%+Lw%?%?%= %{g}][%{B} %d/%m %{W}%c %{g}]'
vbell off
EOF

cat >> /etc/profile << \EOF

if [ $USER == "root" ]; then
  PS1='\[\033[01;31m\]\h\[\033[01;34m\] \W \$\[\033[00m\] '
else
  PS1='\[\033[01;32m\]\u@\h\[\033[01;34m\] \w \$\[\033[00m\] '
fi

[ -x /usr/bin/mc-wrapper.sh ] && alias mc='. /usr/bin/mc-wrapper.sh --nomouse'

alias ssh='ssh -y -i $HOME/.ssh/id_rsa'
EOF

sed -i '/^exit 0/i echo -e "Subject: Reboot `uci get system.@system[0].hostname`.`uci get dhcp.@dnsmasq[0].domain`\\n\\nOpenwrt rebooted: `date; uptime`\\n\\n`grep -B 50 \\"syslogd started\\" /etc/messages`" | sendmail petr.ruzicka@gmail.com' /etc/rc.local

sed -i 's/HISTORY=3/HISTORY=30/' /etc/sysstat/config

mkdir /home
useradd --shell /bin/ash --password $(openssl passwd -1 xxxx) --create-home --comment "Petr Ruzicka" ruzickap
mkdir /home/ruzickap/.ssh
cp /etc/dropbear/authorized_keys /home/ruzickap/.ssh/
chown -R ruzickap:ruzickap /home/ruzickap/.ssh

cat > /etc/rsyncd.conf << EOF
max connections = 3
timeout = 300
dont compress = *

[data]
  comment = data
  path = /data
  read only = yes
  list = yes
EOF

echo "vm.swappiness=5" >> /etc/sysctl.conf
```

Configure the DDNS - duckdns.org:

```bash
uci set ddns.myddns.enabled=1
uci set ddns.myddns.service_name=duckdns.org
uci set ddns.myddns.domain=gate
uci set ddns.myddns.username=NA
uci set ddns.myddns.password=xxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
uci set ddns.myddns.ip_source=network
uci set ddns.myddns.ip_network=wan
uci set ddns.myddns.force_interval=72
uci set ddns.myddns.force_unit=hours
uci set ddns.myddns.check_interval=10
uci set ddns.myddns.check_unit=minutes
uci set 'ddns.myddns.update_url=http://www.duckdns.org/update?domains=[DOMAIN]&token=[PASSWORD]&ip=[IP]'
```

Here are some details about thermometers:

[DS18S20 article](https://web.archive.org/web/20130219033601/http://www.linuxfocus.org/English/November2003/article315.shtml)

[https://martybugs.net/electronics/tempsensor/hardware.cgi](https://martybugs.net/electronics/tempsensor/hardware.cgi)

Configure thermometers:

```bash
digitemp_DS9097 -a -i -c /etc/digitemp.conf -s /dev/ttyUSB0

cat > /etc/digitemp.script << EOF
#!/bin/sh
/usr/bin/digitemp_DS9097 -c/etc/digitemp.conf -a -n0 -d10 -q -s/dev/ttyUSB0 -o"PUTVAL `uci get system.@system[0].hostname`/temp/temperature-%s interval=10 %N:%.2C"
EOF
chmod a+x /etc/digitemp.script
```

Replace uhttpd by lighttpd, configure SSL and mod_proxy for [Transmission](https://transmissionbt.com/):

```bash
/etc/init.d/uhttpd disable
/etc/init.d/uhttpd stop
/etc/init.d/lighttpd enable

mkdir -p /www/myadmin/luci
mv /www/index.html /www/myadmin/luci/
wget --no-check-certificate https://raw.github.com/ruzickap/medlanky.xvx.cz/gh-pages/index.html -O - | sed 's@facebook.com/medlanky@xvx.cz@g;s/UA-6594742-7/UA-6594742-8/' > /www/index.html

uci add firewall rule
uci set firewall.@rule[-1].name=https
uci set firewall.@rule[-1].src=wan
uci set firewall.@rule[-1].target=ACCEPT
uci set firewall.@rule[-1].proto=tcp
uci set firewall.@rule[-1].dest_port=443

uci add firewall rule
uci set firewall.@rule[-1].name=http
uci set firewall.@rule[-1].src=wan
uci set firewall.@rule[-1].target=ACCEPT
uci set firewall.@rule[-1].proto=tcp
uci set firewall.@rule[-1].dest_port=80

mkdir -p /etc/lighttpd/ssl/xvx.cz
chmod 0600 /etc/lighttpd/ssl/xvx.cz

SUBJ="
C=CZ
ST=Czech Republic
O=XvX, Inc.
localityName=Brno
commonName=xvx.cz Certificate Authority
"

openssl req -new -x509 -subj "$(echo -n "$SUBJ" | tr "\n" "/")" -keyout /etc/lighttpd/ssl/xvx.cz/server.pem -out /etc/lighttpd/ssl/xvx.cz/server.pem -days 3650 -nodes

cat >> /etc/lighttpd/lighttpd.conf << \EOF

server.port = 80

$SERVER["socket"] == ":443" {
  ssl.engine                  = "enable"
  ssl.pemfile                 = "/etc/lighttpd/ssl/xvx.cz/server.pem"
}

server.modules = (
 "mod_proxy",
 "mod_cgi",
)

cgi.assign = ( "luci" => "/usr/bin/lua" )

server.errorlog-use-syslog = "enable"
server.dir-listing = "enable"

$HTTP["url"] =~ "^/myadmin/transmission*" {
  # Use proxy for redirection to Transmission's own web interface
  proxy.server = ( "" =>
    ( (
      "host" => "127.0.0.1",
      "port" => 9091
    ) )
  )
}
EOF
```

Make outgoing emails to reach the SMTP server:

```bash
sed -i 's/^mailhub=.*/mailhub=mail.upcmail.cz/;s/^rewriteDomain=.*/rewriteDomain=xvx.cz/' /etc/ssmtp/ssmtp.conf
```

Configure TFTPboot and dnsmasq script:

```bash
mkdir /tftpboot

wget -P /tftpboot <http://static.netboot.me/gpxe/netbootme.kpxe>
uci set dhcp.@dnsmasq[0].enable_tftp=1
uci set dhcp.@dnsmasq[0].tftp_root=/tftpboot
uci set dhcp.@dnsmasq[0].dhcp_boot=netbootme.kpxe

echo "dhcp-script=/etc/dnsmasq-script.sh" >> /etc/dnsmasq.conf

cat > /etc/dnsmasq-script.sh > /etc/dnsmasq.script.log

if [ "$1" == "add" ] && ! grep -iq $2 /etc/config/dhcp; then
 echo -e "Subject: New MAC on `uci get system.@system[0].hostname`.`uci get dhcp.@dnsmasq[0].domain`\\n\\n`/bin/date +"%F %T"` $*" | sendmail <petr.ruzicka@gmail.com>
fi
EOF

chmod a+x /etc/dnsmasq-script.sh
```

Watchcat is used to monitor network connection "pingability" to `8.8.8.8`
otherwise the router is rebooted.

Configure QoS:

```bash
uci set qos.wan.upload=500 # Upload speed in kBits/s
uci set qos.wan.download=5000 # Download speed in kBits/s
uci set qos.wan.enabled=1
sed -i "s/'22,53'/'22,2222,53'/" /etc/config/qos
/etc/init.d/qos enable
```

Configure statistics (collectd):

```bash
mkdir -p /etc/collectd/conf.d

uci set luci_statistics.collectd_rrdtool.DataDir=/etc/collectd
uci set luci_statistics.collectd_ping.enable=1
uci set luci_statistics.collectd_ping.Hosts=www.google.com
uci set luci_statistics.collectd_df.enable=1
uci set luci_statistics.collectd_df.Devices=/dev/sda1
uci set luci_statistics.collectd_df.MountPoints=/overlay
uci set luci_statistics.collectd_df.FSTypes=ext3
uci set luci_statistics.collectd_disk.enable=1
uci set luci_statistics.collectd_disk.Disks=sda
uci set luci_statistics.collectd_dns.enable=1
uci set luci_statistics.collectd_dns.Interfaces=any
uci set luci_statistics.collectd_interface.Interfaces="eth0.2 wlan0 wlan0-1 eth0.1"
uci set luci_statistics.collectd_iptables.enable=0
uci set luci_statistics.collectd_irq.enable=1
uci set luci_statistics.collectd_processes.Processes="lighttpd collectd transmission-daemon"
uci set luci_statistics.collectd_tcpconns.LocalPorts="2222 443 80"
uci set luci_statistics.collectd_olsrd.enable=0
uci set luci_statistics.collectd_rrdtool.CacheTimeout=120
uci set luci_statistics.collectd_rrdtool.CacheFlush=900

uci set luci_statistics.collectd_exec.enable=1
uci commit
uci add luci_statistics collectd_exec_input
uci set luci_statistics.@collectd_exec_input[-1].cmdline="/etc/digitemp.script"

cat > /etc/collectd/conf.d/my_collectd.conf
 LogLevel "info"

EOF
```

Configure vnstat - software for monitoring / graphing network throughput:

```bash
mkdir /etc/vnstat
sed -i 's@^\(DatabaseDir\).*@\1 "/overlay/etc/vnstat"@' /etc/vnstat.conf
vnstat -u -i eth0.2
vnstat -u -i wlan0
vnstat -u -i wlan0-1
vnstat -u -i eth0.1

echo "*/5 * * * * vnstat -u" >> /etc/crontabs/root

cat > /etc/graphs-vnstat.sh << \EOF
#!/bin/sh
# vnstati image generation script.
# Source:  https://code.google.com/p/x-wrt/source/browse/package/webif/files/www/cgi-bin/webif/graphs-vnstat.sh

WWW_D=/www/myadmin/vnstat # output images to here
LIB_D=`awk -F \" '/^DatabaseDir/ { print $2 }' /etc/vnstat.conf` # db location
BIN=/usr/bin/vnstati  # which vnstati

outputs="s h d t m"   # what images to generate

# Sanity checks
[ -d "$WWW_D" ] || mkdir -p "$WWW_D" # make the folder if it doesn't exist.

# End of config changes
interfaces="$(ls -1 $LIB_D)"

if [ -z "$interfaces" ]; then
    echo "No database found, nothing to do."
    echo "A new database can be created with the following command: "
    echo "    vnstat -u -i eth0"
    exit 0
else
    for interface in $interfaces; do
        for output in $outputs; do
            $BIN -${output} -i $interface -o $WWW_D/vnstat_${interface}_${output}.png
        done
    done
fi

exit 1
EOF

chmod a+x /etc/graphs-vnstat.sh
echo "0 2 * * * /etc/graphs-vnstat.sh" >> /etc/crontabs/root

cat > /www/myadmin/vnstat/index.html << EOF
<META HTTP-EQUIV="refresh" CONTENT="300">
<html>
  <head>
    <title>Traffic of OpenWRT interfaces</title>
  </head>
  <body>
EOF

for IFCE in $(ls -1 `awk -F \" '/^DatabaseDir/ { print $2 }' /etc/vnstat.conf`); do
cat >> /www/myadmin/vnstat/index.html << EOF
    <h2>Traffic of Interface $IFCE</h2>
    <table>
        <tbody>
            <tr>
                <td>
                    <img src="vnstat_${IFCE}_s.png" alt="$IFCE Summary" />
                </td>
                <td>
                    <img src="vnstat_${IFCE}_h.png" alt="$IFCE Hourly" />
                </td>
            </tr>
            <tr>
                <td valign="top">
                    <img src="vnstat_${IFCE}_d.png" alt="$IFCE Daily" />
                </td>
                <td valign="top">
                    <img src="vnstat_${IFCE}_t.png" alt="$IFCE Top 10" />
                    <br />
                    <img src="vnstat_${IFCE}_m.png" alt="$IFCE Monthly" />
                </td>
            </tr>
        </tbody>
    </table>
EOF
done

cat >> /www/myadmin/vnstat/index.html << EOF
  </body>
</html>
EOF
```

Configure the nodogsplash for `wifi_open` (guests):

```bash
mv /etc/nodogsplash/nodogsplash.conf /etc/nodogsplash/nodogsplash.conf-orig

cat > /etc/nodogsplash/nodogsplash.conf << EOF
GatewayInterface br-wifi_open

FirewallRuleSet authenticated-users {
    FirewallRule block to 192.168.0.0/16
    FirewallRule block to 10.0.0.0/8
    FirewallRule allow tcp port 53
    FirewallRule allow udp port 53
    FirewallRule allow tcp port 80
    FirewallRule allow tcp port 443
    FirewallRule allow tcp port 22
    FirewallRule allow icmp
}

FirewallRuleSet preauthenticated-users {
    FirewallRule allow tcp port 53
    FirewallRule allow udp port 53
}

FirewallRuleSet users-to-router {
    FirewallRule allow udp port 53
    FirewallRule allow tcp port 53
    FirewallRule allow udp port 67
    FirewallRule allow icmp
}

GatewayName medlanky.xvx.cz
RedirectURL http://medlanky-hotspot.xvx.cz/
ClientForceTimeout 120
EOF

sed -i 's@#OPTIONS="-s -d 5"@OPTIONS="-s -d 5"@' /etc/init.d/nodogsplash

wget "http://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/Brno-Medl%C3%A1nky_znak.svg/90px-Brno-Medl%C3%A1nky_znak.svg.png" -O /etc/nodogsplash/htdocs/images/90px-Brno-Medlanky_znak.svg.png

cp /etc/nodogsplash/htdocs/splash.html /etc/nodogsplash/htdocs/splash.html-orig
sed -i 's@wifidog.png.*@90px-Brno-Medlanky_znak.svg.png"@;/align=center height="120">/a\
\ \ <h2>For Internet access - click the sign.</h2> <h2>Pro pristup na Internet klikni na znak.</h2>\
' /etc/nodogsplash/htdocs/splash.html

/etc/init.d/nodogsplash enable
```

Transmission bittorrent client configuration:

```bash
mkdir -p /data/torrents/torrents-completed /data/torrents/torrents-incomplete /data/torrents/torrents /data/torrents/config

ln -s /data/torrents/torrents /home/ruzickap/torrents
chown -R ruzickap:ruzickap /data/torrents/torrents

uci set transmission.@transmission[-1].enabled=1
uci set transmission.@transmission[-1].config_dir=/data/torrents/config
uci set transmission.@transmission[-1].download_dir=/data/torrents/torrents-completed
uci set transmission.@transmission[-1].incomplete_dir_enabled=true
uci set transmission.@transmission[-1].incomplete_dir=/data/torrents/torrents-incomplete
uci set transmission.@transmission[-1].blocklist_enabled=1
uci set "transmission.@transmission[-1].blocklist_url=<http://list.iblocklist.com/?list=bt_level1&fileformat=p2p&archiveformat=zip>"
uci set transmission.@transmission[-1].speed_limit_down_enabled=true
uci set transmission.@transmission[-1].speed_limit_up_enabled=true
uci set transmission.@transmission[-1].speed_limit_down=300
uci set transmission.@transmission[-1].speed_limit_up=5
uci set transmission.@transmission[-1].alt_speed_enabled=true
uci set transmission.@transmission[-1].alt_speed_down=99999
uci set transmission.@transmission[-1].alt_speed_up=10
uci set transmission.@transmission[-1].alt_speed_time_enabled=true
uci set transmission.@transmission[-1].alt_speed_time_day=127
uci set transmission.@transmission[-1].alt_speed_time_begin=60
uci set transmission.@transmission[-1].alt_speed_time_end=420
uci set transmission.@transmission[-1].rpc_whitelist_enabled=false
uci set transmission.@transmission[-1].start_added_torrents=true
uci set transmission.@transmission[-1].script_torrent_done_enabled=true
uci set transmission.@transmission[-1].script_torrent_done_filename=/etc/torrent-done.sh
uci set transmission.@transmission[-1].watch_dir_enabled=true
uci set transmission.@transmission[-1].watch_dir=/data/torrents/torrents/
uci set transmission.@transmission[-1].rpc_url=/myadmin/transmission/
uci set transmission.@transmission[-1].rpc_authentication_required=true
uci set transmission.@transmission[-1].rpc_username=ruzickap
uci set transmission.@transmission[-1].rpc_password=xxxx
uci set transmission.@transmission[-1].ratio_limit=0
uci set transmission.@transmission[-1].ratio_limit_enabled=true
uci set transmission.@transmission[-1].upload_slots_per_torrent=5
uci set transmission.@transmission[-1].trash_original_torrent_files=true
uci set transmission.@transmission[-1].download_queue_size=1

uci add firewall rule
uci set firewall.@rule[-1].name=transmission
uci set firewall.@rule[-1].src=wan
uci set firewall.@rule[-1].target=ACCEPT
uci set firewall.@rule[-1].proto=tcpudp
uci set firewall.@rule[-1].dest_port=51413

/etc/init.d/transmission enable
/etc/init.d/miniupnpd enable

cat > /etc/torrent-done.sh << \EOF

## !/bin/sh

echo -e "Subject: $TR_TORRENT_NAME finished.\n\nTransmission finished downloading \"$TR_TORRENT_NAME\" on $TR_TIME_LOCALTIME" | /usr/sbin/ssmtp <petr.ruzicka@gmail.com>
EOF
chmod a+x /etc/torrent-done.sh

uci commit
reboot
```

I'm sure you need to customize most of the thing mentioned above, but these
notes can still help you.

Enjoy :-)
