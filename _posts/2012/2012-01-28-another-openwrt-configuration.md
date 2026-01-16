---
title: Another OpenWrt configuration
author: Petr Ruzicka
date: 2012-01-28
description: ""
categories: [Linux, OpenWrt]
tags: [TP-Link, WiFi, USB, PXE, Dnsmasq, iodine]
---

> <https://linux-old.xvx.cz/2012/01/another-openwrt-configuration/>
{: .prompt-info }

I would like to describe another [OpenWrt](https://openwrt.org/) configuration.
It's going to be just a few examples on how to configure the latest available
OpenWrt firmware [Backfire 10.03.1](https://downloads.openwrt.org/backfire/10.03.1/).

I'm going to use [TP-Link
TL-WR1043ND](https://www.tp-link.com/en/products/details/?model=TL-WR1043ND) wifi
router with small 64MB USB stick `/dev/sda1` containing ext2 partition. I plan
to have some stats on the USB stick and simple html pages as well.

<!-- rumdl-disable MD013 -->
After flashing the original firmware with [openwrt-ar71xx-tl-wr1043nd-v1-squashfs-factory.bin](https://downloads.openwrt.org/backfire/10.03.1/ar71xx/openwrt-ar71xx-tl-wr1043nd-v1-squashfs-factory.bin)
I installed the kernel related packages and
[extroot](https://wiki.openwrt.org/doc/howto/extroot):
<!-- rumdl-enable MD013 -->

(if you have OpenWRT already installed use: `mtd -e firmware -r write
/www2/openwrt-ar71xx-tl-wr1043nd-v1-squashfs-sysupgrade.bin firmware`)

```bash
telnet 192.168.1.1
passwd

opkg update
opkg install block-hotplug block-extroot kmod-fs-ext4 kmod-usb-storage

uci set system.@system[0].hostname=openwrt
uci set system.@system[0].timezone=CET-1CEST,M3.5.0,M10.5.0/3
uci set system.@system[0].timezone=CET-1CEST,M3.5.0,M10.5.0/3
uci set system.@system[0].log_file=/etc/messages
uci set system.@system[0].log_size=1024
uci set system.@system[0].log_type=file

uci set fstab.@mount[0].device=/dev/sda1
uci set fstab.@mount[0].fstype=ext4
uci set fstab.@mount[0].options=rw,sync
uci set fstab.@mount[0].enabled=1
uci set fstab.@mount[0].enabled_fsck=0
uci set fstab.@mount[0].is_rootfs=1

uci set dropbear.@dropbear[0].Port=2222

uci add firewall rule
uci set firewall.@rule[-1].name=ssh
uci set firewall.@rule[-1].src=wan
uci set firewall.@rule[-1].target=ACCEPT
uci set firewall.@rule[-1].proto=tcp
uci set firewall.@rule[-1].dest_port=2222

uci add firewall rule
uci set firewall.@rule[-1].name=iodined
uci set firewall.@rule[-1].src=wan
uci set firewall.@rule[-1].target=ACCEPT
uci set firewall.@rule[-1].proto=udp
uci set firewall.@rule[-1].dest_port=53

uci add firewall rule
uci set firewall.@rule[-1].name=snmp
uci set firewall.@rule[-1].src=wan
uci set firewall.@rule[-1].target=ACCEPT
uci set firewall.@rule[-1].proto=udp
uci set firewall.@rule[-1].dest_port=161

uci add firewall rule
uci set firewall.@rule[-1].name=http_ser
uci set firewall.@rule[-1].src=lan
uci set firewall.@rule[-1].dst=wan
uci set firewall.@rule[-1].src_ip=192.168.0.0/24
uci set firewall.@rule[-1].target=ACCEPT
uci set firewall.@rule[-1].proto=tcp
uci set firewall.@rule[-1].dest_port=80

uci set wireless.@wifi-iface[-1].ssid=ser
uci set wireless.@wifi-iface[-1].encryption=psk2
uci set wireless.@wifi-iface[-1].key=xxxxxxxx

uci set wireless.radio0.channel=3
uci set wireless.radio0.htmode=HT40

uci del wireless.@wifi-device[0].disabled

uci set network.lan.ipaddr=192.168.0.1

uci set dhcp.@dnsmasq[0].domain=ser.no-ip.org
uci set dhcp.@dnsmasq[0].leasefile=/etc/dnsmasq-dhcp.leases
uci set dhcp.@dnsmasq[0].port=0
uci set dhcp.@dnsmasq[0].cachelocal=0
uci set dhcp.lan.dhcp_option=6,8.8.8.8

uci set dhcp.lan.start=200
uci set dhcp.lan.limit=254

uci add dhcp host
uci set dhcp.@host[-1].name=ruz
uci set dhcp.@host[-1].ip=192.168.0.2
uci set dhcp.@host[-1].mac=XX:XX:XX:XX:XX:XX
```

Configure the ssh to enable autologin:

```bash
scp "$HOME/.ssh/id_rsa.pub" root@192.168.1.1:/tmp/authorized_keys
ssh root@192.168.1.1
cp /tmp/authorized_keys /etc/dropbear/authorized_keys
chmod 600 /etc/dropbear/authorized_keys
```

Install few applications:

```bash
opkg update
opkg install --force-overwrite htop less openssh-sftp-server tcpdump wget-nossl
```

Configure ssmtp for the outgoing emails:

```bash
opkg install msmtp-nossl

sed -i 's/^\(host\).*/\1 smtp.XXXXXX.cz/' /etc/msmtprc
cat >> /etc/msmtprc << EOF
auto_from on
maildomain ser.no-ip.org
EOF

# shellcheck disable=SC2016 # Single quotes intentional - backticks expand on router, not locally
sed -i '/^exit 0/i echo -e "Subject: Reboot `uci get system.@system[0].hostname`\\n\\nOpenwrt rebooted: `date`\\n\\n`grep -B 50 \\"syslogd started\\" /etc/messages`" | sendmail petr.ruzicka@gmail.com' /etc/rc.local
```

Configure DDNS:

```bash
opkg install luci-app-ddns

uci set ddns.myddns.enabled=1
uci set ddns.myddns.service_name=no-ip.com
uci set ddns.myddns.domain=ser.no-ip.org
uci set ddns.myddns.username=ruz
uci set ddns.myddns.password=XXXXXXXXXXX
```

Install snmpd:

```bash
opkg install mini-snmpd

uci set mini_snmpd.@mini_snmpd[0].interfaces=lo,br-lan,eth0.2,eth0.1
uci set mini_snmpd.@mini_snmpd[0].community=OpenWrt
uci set mini_snmpd.@mini_snmpd[0].location='Ser'
uci set mini_snmpd.@mini_snmpd[0].contact='Ser'
uci set mini_snmpd.@mini_snmpd[0].disks='/tmp,/overlay'

/etc/init.d/mini_snmpd enable
```

Configure TFTPboot and dnsmasq script:

```bash
mkdir /tftpboot

wget -P /tftpboot http://static.netboot.me/gpxe/netbootme.kpxe
uci set dhcp.@dnsmasq[0].enable_tftp=1
uci set dhcp.@dnsmasq[0].tftp_root=/tftpboot
uci set dhcp.@dnsmasq[0].dhcp_boot=netbootme.kpxe

echo "dhcp-script=/etc/dnsmasq-script.sh" >> /etc/dnsmasq.conf

cat > /etc/dnsmasq-script.sh << \EOF
#!/bin/sh

/bin/echo `/bin/date +"%F %T"` $* >> /www2/dnsmasq.script.log

if [ "$1" == "add" ] && ! grep -iq $2 /etc/config/dhcp; then
  echo -e "Subject: New MAC on `uci get system.@system[0].hostname`.`uci get dhcp.@dnsmasq[0].domain`\\n\\n`/bin/date +"%F %T"` $*" | sendmail petr.ruzicka@gmail.com
fi
EOF

chmod a+x /etc/dnsmasq-script.sh
```

Configuration of iodined server (dns-tunelling)

```bash
opkg install iodined

uci set iodined.@iodined[0].address=XX.XXX.XX.XX
uci set iodined.@iodined[0].password=XXXXXXXX
uci set iodined.@iodined[0].tunnelip=192.168.99.1
uci set iodined.@iodined[0].tld=tunnel.XXXXX.cz

/etc/init.d/iodined enable
```

Configure httpd daemon for the `/www2`:

```bash
opkg install px5g uhttpd-mod-tls

uci del uhttpd.main.listen_http
uci set uhttpd.px5g.days=3650
uci set uhttpd.px5g.country=CZ
uci set uhttpd.px5g.state="Czech Republic"
uci set uhttpd.px5g.location=Brno
rm /etc/uhttpd.crt /etc/uhttpd.key

uci set uhttpd.main.listen_https="0.0.0.0:443"

mkdir -p /www2/vnstat
uci set uhttpd.my=uhttpd
uci set uhttpd.my.listen_http="0.0.0.0:80"
uci set uhttpd.my.home=/www2
```

Set the checking time for watchcat for 1 hour:

```bash
opkg install watchcat

/etc/uci-defaults/50-watchcat
uci set system.@watchcat[0].period=1h

/etc/init.d/watchcat enable
uci commit
reboot
```

Repeat the previous steps and continue...
You need to repeat it, because your router now reads the configs from "empty"
USB stick and not form internal memory. If you will remove the USB stick openwrt
will read the configs from the memory.

Configure statistics (collectd):

```bash
opkg install luci-app-statistics

opkg install collectd-mod-cpu collectd-mod-disk collectd-mod-irq collectd-mod-ping collectd-mod-processes collectd-mod-tcpconns

uci set luci_statistics.collectd_rrdtool.DataDir=/etc/collectd
uci set luci_statistics.collectd_ping.enable=1
uci set luci_statistics.collectd_ping.Hosts=www.google.com
uci set luci_statistics.collectd_df.enable=1
uci set luci_statistics.collectd_df.Devices=/dev/sda1
uci set luci_statistics.collectd_df.MountPoints=/overlay
uci set luci_statistics.collectd_df.FSTypes=fuseblk
uci set luci_statistics.collectd_disk.enable=1
uci set luci_statistics.collectd_disk.Disks=sda
uci set luci_statistics.collectd_interface.Interfaces="eth0.2 wlan0 eth0.1"
uci set luci_statistics.collectd_irq.enable=1
uci set luci_statistics.collectd_tcpconns.LocalPorts="2222 80 443"
uci set luci_statistics.collectd_rrdtool.CacheTimeout=120
uci set luci_statistics.collectd_rrdtool.CacheFlush=900

/etc/init.d/luci_statistics enable
/etc/init.d/collectd enable
opkg install luci-app-vnstat vnstat vnstati

mkdir /etc/vnstat
sed -i 's@^\(DatabaseDir\).*@\1 "/overlay/etc/vnstat"@' /etc/vnstat.conf
vnstat -u -i eth0.2
vnstat -u -i wlan0
vnstat -u -i eth0.1
/etc/init.d/vnstat enable
/etc/init.d/vnstat start
echo "*/5 * * * * vnstat -u" >> /etc/crontabs/root

cat > /etc/graphs-vnstat.sh << \EOF
#!/bin/sh
# vnstati image generation script.
# Source: http://code.google.com/p/x-wrt/source/browse/trunk/package/webif/files/www/cgi-bin/webif/graphs-vnstat.sh

WWW_D=/www2/vnstat # output images to here
LIB_D=`awk -F \" '/^DatabaseDir/ { print $2 }' /etc/vnstat.conf` # db location
BIN=/usr/bin/vnstati  # which vnstati

outputs="s h d t m"   # what images to generate

# Sanity checks
[ -d "$WWW_D" ] || mkdir -p "$WWW_D" # make the folder if it dont exist.

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
echo "*/31 * * * * /etc/graphs-vnstat.sh" >> /etc/crontabs/root

cat > /www2/vnstat/index.html << \EOF
<META HTTP-EQUIV="refresh" CONTENT="300">
<html>
  <head>
    <title>Traffic of OpenWRT interfaces</title>
  </head>
  <body>
EOF

for IFCE in "$(awk -F \" '/^DatabaseDir/ { print $2 }' /etc/vnstat.conf)"/*; do
  cat >> /www2/vnstat/index.html << EOF
    <h3>Traffic of Interface $IFCE</h3>
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

                    <img src="vnstat_${IFCE}_m.png" alt="$IFCE Monthly" />
                </td>
            </tr>
        </tbody>
    </table>
EOF
done

cat >> /www2/vnstat/index.html << \EOF
  </body>
</html>
EOF
```

Configure the nodogsplash:

```bash
opkg install nodogsplash

cp nodogsplash.conf nodogsplash.conf-orig
sed -i "s/\(^GatewayInterface\).*/\1 br-lan/;s/^# \(GatewayName\).*/\1 Ser/;s/\(.*FirewallRule allow tcp port 80\)$/#\1/;s@^# \(GatewayIPRange\).*@\1 192.168.0.192/26@;/FirewallRule block to 10.0.0.0\/8/a\ \ \ \ FirewallRule allow tcp port 80" /etc/nodogsplash/nodogsplash.conf

sed -i "/<td align=center height=\"120\">/a\
<h3>For Internet access - click the dog</h3>\
<h3>Pro pristup na Internet klikni na psa.</h3>\
" /etc/nodogsplash/htdocs/splash.html

/etc/init.d/nodogsplash enable

uci commit
reboot
```

That's all... ;-) Happy OpenWRTing...
