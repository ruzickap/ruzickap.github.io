---
title: OpenWrt with Transmission, Samba and vsftpd
author: Petr Ruzicka
date: 2010-12-01
description: ""
categories: [OpenWrt, Networking, linux-old.xvx.cz]
tags: [tp-link, torrent]
---

> <https://linux-old.xvx.cz/2010/12/openwrt-with-transmission-samba-and-vsftpd/>
{: .prompt-info }

My brother asked me to customize firmware in his WiFi router
[TP-Link TL-WR1043ND](https://openwrt.org/toh/tp-link/tl-wr1043nd).
He wants to use it for downloading torrents and sharing them using smb and ftp
protocols.

I have good experience with [OpenWrt](https://openwrt.org/), which is really
good in customization and suits well for this purpose. Nowadays there are
a few torrent clients in OpenWrt distribution, but I chose
[transmission](https://transmissionbt.com/) and for ftp daemon
[vsftpd](https://security.appspot.com/vsftpd.html).

I decided to compile it from scratch (using Fedora 13), because I'm able to
include all necessary software in the image (since it's compressed). If I
install the packages using `opkg` later I will not have enough free space to
install all my favorite programs.

Here are my notes beginning with the compilation from sources, uploading
firmware and basic OpenWrt configuration.

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
cd backfire || exit

./scripts/feeds update

./scripts/feeds install block-extroot e2fsprogs cifsmount collectd-mod-conntrack collectd-mod-contextswitch collectd-mod-cpu collectd-mod-df collectd-mod-disk collectd-mod-dns collectd-mod-exec collectd-mod-filecount collectd-mod-iptables collectd-mod-irq collectd-mod-memory collectd-mod-netlink collectd-mod-network collectd-mod-ping collectd-mod-processes collectd-mod-protocols collectd-mod-syslog collectd-mod-tcpconns collectd-mod-uptime collectd-mod-users collectd-mod-vmem darkstat htop kmod-ath9k kmod-usb2 kmod-usb-storage luci-app-livestats luci-app-ntpc luci-app-qos luci-app-samba luci-app-statistics luci-ssl mc mini-snmpd mount.ntfs-3g nmap ntfs-3g ssmtp tcpdump-mini transmission-web vsftpd wget wpad-mini zoneinfo-europe

make menuconfig
```

Now you should select what you want to have in the final firmware image. I just
selected what I installed from the feeds above (my
[.config](https://ftp.xvx.cz/pub/distributions/openwrt/bracha/.config)):

Then run

```bash
make V=99
```

... and take a coffee :-)

Connect router to your desktop/laptop and flash it from the webgui using
this file: [openwrt-ar71xx-tl-wr1043nd-v1-squashfs-factory.bin](https://ftp.xvx.cz/pub/distributions/openwrt/bracha/openwrt-ar71xx-tl-wr1043nd-v1-squashfs-factory.bin)

If you already have OpenWrt installed you can replace it by this command:

```bash
sysupgrade -v -i ftp://ftp.xvx.cz/pub/distributions/openwrt/bracha/openwrt-ar71xx-tl-wr1043nd-v1-squashfs-sysupgrade.bin
# scp ./backfire/bin/ar71xx/openwrt-ar71xx-tl-wr1043nd-v1-squashfs-sysupgrade.bin root@192.168.0.2:/tmp
# sysupgrade -v -i /tmp/openwrt-ar71xx-tl-wr1043nd-v1-squashfs-sysupgrade.bin
# or
# mtd -r write /tmp/openwrt-ar71xx-tl-wr1043nd-v1-squashfs-sysupgrade.bin firmware
```

Set password using telnet command and continue with firewall, network and other
system stuff :

```bash
ifconfig eth0 192.168.1.2 netmask 255.255.255.0
telnet 192.168.1.1
passwd

uci add firewall rule
uci set firewall.@rule[-1].name=ssh
uci set firewall.@rule[-1].src=wan
uci set firewall.@rule[-1].target=ACCEPT
uci set firewall.@rule[-1].proto=tcp
uci set firewall.@rule[-1].dst_port=22

uci add firewall rule
uci set firewall.@rule[-1].name=ftp
uci set firewall.@rule[-1].src=wan
uci set firewall.@rule[-1].target=ACCEPT
uci set firewall.@rule[-1].proto=tcp
uci set firewall.@rule[-1].dst_port=21

uci add firewall rule
uci set firewall.@rule[-1].name=snmp
uci set firewall.@rule[-1].src=wan
uci set firewall.@rule[-1].target=ACCEPT
uci set firewall.@rule[-1].proto=udp
uci set firewall.@rule[-1].dst_port=161

uci add firewall rule
uci set firewall.@rule[-1].name=transmission
uci set firewall.@rule[-1].src=wan
uci set firewall.@rule[-1].target=ACCEPT
uci set firewall.@rule[-1].proto=tcp
uci set firewall.@rule[-1].dst_port=51413

uci set wireless.@wifi-iface[-1].ssid=kerova11
uci set wireless.@wifi-iface[-1].encryption=psk2
uci set wireless.@wifi-iface[-1].key=xxxxxxxx
uci set wireless.@wifi-iface[-1].network=lan

uci set wireless.radio0.channel=3
uci set wireless.radio0.htmode=HT40
uci del wireless.@wifi-device[0].disabled

uci set dhcp.@dnsmasq[0].notinterface="eth0.2"

#uci set dhcp.wifi=dhcp
#uci set dhcp.wifi.interface=wifi
#uci set dhcp.wifi.start=10
#uci set dhcp.wifi.limit=250

uci add dhcp host
uci set dhcp.@host[-1].name=jura_nb
uci set dhcp.@host[-1].ip=192.168.1.5
uci set dhcp.@host[-1].mac=00:21:5d:70:61:de

uci add dhcp host
uci set dhcp.@host[-1].name=jura_pda
uci set dhcp.@host[-1].ip=192.168.1.6
uci set dhcp.@host[-1].mac=00:1a:6b:95:ae:26

uci set system.@system[0].hostname=OpenWrt-bracha
uci set system.@system[0].timezone=CET-1CEST,M3.5.0,M10.5.0/3
uci set system.@system[0].timezone=CET-1CEST,M3.5.0,M10.5.0/3
uci set system.@system[0].log_size=64
uci set system.@system[0].log_ip=gate.xvx.cz

uci set qos.wan.upload=819200
uci set qos.wan.download=819200

uci commit
reboot
```

Try if you are able to mount NTFS drives and create swap on it:

```bash
echo "ruzicka:*:1000:1000:ruzicka:/tmp:/bin/false" >> /etc/passwd
mkdir /mnt/sda1
#mount /dev/sda1 /mnt/sda1
ntfs-3g -o rw,utf8,fmask=0133,dmask=0022,noatime,uid=1000 /dev/sda1 /mnt/sda1
mkdir -p /mnt/samba /mnt/sda1/openwrt/shared /mnt/sda1/openwrt/torrent-incomplete /mnt/sda1/openwrt/torrent /mnt/sda1/openwrt/collectd_rrdtool /mnt/sda1/openwrt/shared/torrent
#swapon /dev/sdb2
dd if=/dev/zero of=/mnt/sda1/openwrt/swap count=262144
mkswap /mnt/sda1/openwrt/swap
swapon /mnt/sda1/openwrt/swap

cat >> /etc/rc.local << EOF
ntfs-3g -o rw,utf8,fmask=0133,dmask=0022,noatime,uid=1000 /dev/sda1 /mnt/sda1 && swapon /mnt/sda1/openwrt/swap &
/etc/init.d/transmission start
/etc/init.d/transmission enable
mount.cifs //192.168.0.1/all /mnt/samba -o guest,nosetuids,nosuid,noperm,noacl,noexec,nodev,nouser_xattr,file_mode=0644,dir_mode=0755 &
exit 0
EOF

#uci set fstab.@swap[0].enabled=1
#uci set fstab.@mount[0].target=/mnt/sda1
#uci set fstab.@mount[0].fstype=ext4
#uci set fstab.@mount[0].enabled=1
```

Setup the ssh key to enable autologin:

```bash
scp "$HOME"/.ssh/id_rsa.pub root@192.168.0.2:/tmp/authorized_keys
ssh root@192.168.0.2
cp /tmp/authorized_keys /etc/dropbear/authorized_keys
chmod 600 /etc/dropbear/authorized_keys
```

Configure certificate details for https:

```bash
uci set uhttpd.px5g.days=3650
uci set uhttpd.px5g.country=CZ
uci set uhttpd.px5g.state="Czech Republic"
uci set uhttpd.px5g.location=Brno
rm /etc/uhttpd.crt /etc/uhttpd.key
```

Configure darkstat and snmpd:

```bash
uci set darkstat.@darkstat[0].interface=wan

uci set mini_snmpd.@mini_snmpd[0].interfaces=lo,eth0.2,wlan0
uci set mini_snmpd.@mini_snmpd[0].community=my_community
uci set mini_snmpd.@mini_snmpd[0].location='Kerova 11, Brno'
uci set mini_snmpd.@mini_snmpd[0].contact='PeRu'
```

Setup ssmtp to be able to send emails:

```bash
sed -i 's/\(^root\)=.*/\1=openwrt.email@gmail.com/;s/\(^mailhub\).*/\1=smtp.gmail.com:587/;s/\(^rewriteDomain=\).*/\1gmail.com/;s/^#\(FromLineOverride=YES\)/\1/;s/^#\(UseTLS=YES\)/\1/' /etc/ssmtp/ssmtp.conf

cat >> /etc/ssmtp/ssmtp.conf << EOF
UseSTARTTLS=YES
AuthUser=openwrt.email
AuthPass=my_password
EOF
```

Samba configuration:

```bash
uci delete samba.@sambashare[-1]
uci delete samba.@samba[-1].homes
uci add samba sambashare
uci set samba.@sambashare[-1].name=shared
uci set samba.@sambashare[-1].path=/mnt/sda1/openwrt/shared
uci set samba.@sambashare[-1].read_only=yes
uci set samba.@sambashare[-1].guest_ok=yes

uci add samba sambashare
uci set samba.@sambashare[-1].name=shared_rw
uci set samba.@sambashare[-1].path=/mnt/sda1/openwrt/shared
uci set samba.@sambashare[-1].read_only=no
uci set samba.@sambashare[-1].guest_ok=no
uci set samba.@sambashare[-1].users=ruzicka

uci add samba sambashare
uci set samba.@sambashare[-1].name=openwrt
uci set samba.@sambashare[-1].path=/mnt/sda1/openwrt
uci set samba.@sambashare[-1].read_only=no
uci set samba.@sambashare[-1].guest_ok=no
uci set samba.@sambashare[-1].users=ruzicka

uci add samba sambashare
uci set samba.@sambashare[-1].name=sda1
uci set samba.@sambashare[-1].path=/mnt/sda1
uci set samba.@sambashare[-1].read_only=no
uci set samba.@sambashare[-1].guest_ok=no
uci set samba.@sambashare[-1].users=ruzicka

sed -i -e 's|security = share|security = user|' /etc/samba/smb.conf.template
sed -i -e 's|ISO-8859-1|UTF-8|' /etc/samba/smb.conf.template
echo -e "\tdisplay charset = UTF8" >> /etc/samba/smb.conf.template
echo -e "\tdos charset = CP852" >> /etc/samba/smb.conf.template

smbpasswd ruzicka testpassword123

/etc/init.d/samba enable
```

FTP configuration:

```bash
sed -i 's/\(^anonymous_enable\).*/\1=YES/;s/^#\(syslog_enable=YES\).*/\1/' /etc/vsftpd.conf
cat >> /etc/vsftpd.conf << EOF
anon_root=/mnt/sda1/openwrt/shared
ftp_username=nobody
hide_ids=YES
EOF

passwd ruzicka
```

Luci statistics module configuration:

```bash
uci set luci_statistics.collectd_ping.enable=1
uci set luci_statistics.collectd_ping.Hosts=www.google.com
uci set luci_statistics.collectd_df.enable=1
uci set luci_statistics.collectd_df.Devices=/dev/sda1
uci set luci_statistics.collectd_df.MountPoints=/mnt/sda1
uci set luci_statistics.collectd_df.FSTypes=fuseblk
uci set luci_statistics.collectd_dns.enable=1
uci set luci_statistics.collectd_dns.Interfaces="eth0.2"
uci set luci_statistics.collectd_interface.Interfaces="eth0.2 wlan0"
uci set luci_statistics.collectd_iptables.enable=0
uci set luci_statistics.collectd_irq.enable=1
uci set luci_statistics.collectd_network.enable=1
uci set luci_statistics.@collectd_network_server[0].host="\"collectd.xvx.cz\""
uci set luci_statistics.collectd_netlink.enable=1
uci set luci_statistics.collectd_netlink.VerboseInterfaces="eth0.2 wlan0"
uci set luci_statistics.collectd_netlink.QDiscs="eth0.2 wlan0"
uci set luci_statistics.collectd_tcpconns.LocalPorts="22 80 443 667"
uci set luci_statistics.collectd_rrdtool.DataDir=/mnt/sda1/openwrt/collectd_rrdtool
uci set luci_statistics.collectd_disk.enable=1
uci set luci_statistics.collectd_disk.Disks=sda

mkdir -p /etc/collectd/conf.d
cat > /etc/collectd/conf.d/my_collectd.conf << EOF
LoadPlugin contextswitch
LoadPlugin memory
LoadPlugin uptime
LoadPlugin vmem

LoadPlugin protocols
<Plugin protocols>
        Value "/^Tcp:/"
        IgnoreSelected false
</Plugin>

LoadPlugin filecount
<Plugin filecount>
    <Directory "/mnt/sda1/openwrt/torrent/torrents">
      Instance "torrents"
      Name "*.torrent"
    </Directory>
</Plugin>

LoadPlugin syslog
<Plugin syslog>
  LogLevel "info"
</Plugin>
EOF
```

Transmission bittorrent client configuration:

```bash
uci set transmission.@transmission[-1].enabled=1
uci set transmission.@transmission[-1].config_dir=/mnt/sda1/openwrt/torrent
uci set transmission.@transmission[-1].download_dir=/mnt/sda1/openwrt/shared/torrent
uci set transmission.@transmission[-1].incomplete_dir_enabled=true
uci set transmission.@transmission[-1].incomplete_dir=/mnt/sda1/openwrt/torrent-incomplete
uci set transmission.@transmission[-1].speed_limit_down_enabled=false
uci set transmission.@transmission[-1].speed_limit_down=100
uci set transmission.@transmission[-1].speed_limit_up=0
uci set transmission.@transmission[-1].alt_speed_enabled=false
uci set transmission.@transmission[-1].alt_speed_down=0
uci set transmission.@transmission[-1].alt_speed_up=10
uci set transmission.@transmission[-1].alt_speed_time_day=127
uci set transmission.@transmission[-1].alt_speed_time_begin=0
uci set transmission.@transmission[-1].alt_speed_time_end=360
uci set transmission.@transmission[-1].rpc_whitelist=127.0.0.1,192.168.1.*
uci set transmission.@transmission[-1].start_added_torrents=true
uci set transmission.@transmission[-1].script_torrent_done_enabled=true
uci set transmission.@transmission[-1].script_torrent_done_filename=/etc/torrent-done.sh

cat > /etc/torrent-done.sh << \EOF
echo -e "$TR_TORRENT_NAME finished." | ssmtp ruzickajiri@gmail.com
EOF
chmod a+x /etc/torrent-done.sh

uci commit
reboot
```

Now you can use one of the transmission clients and try to download something.

I'm sure you need to customize most of the things mentioned above, but these
notes can still help you.

Enjoy :-)
