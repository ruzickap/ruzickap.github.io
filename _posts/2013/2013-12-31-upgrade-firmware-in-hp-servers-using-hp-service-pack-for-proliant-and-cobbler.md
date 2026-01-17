---
title: Upgrade firmware in HP servers using HP Service Pack for ProLiant and Cobbler
author: Petr Ruzicka
date: 2013-12-31
description: Upgrade firmware in HP servers using HP Service Pack for ProLiant and Cobbler
categories: [Linux, Networking]
tags: [hp-server, cobbler, pxe]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2013/12/upgrade-firmware-in-hp-servers-using-hp.html)
{: .prompt-info }

If you have to upgrade the firmware (iLO, BIOS, Disk firmware, NIC firmware,
...) inside many HP servers and for this task it's useful to use
[HP Service Pack for ProLiant](https://web.archive.org/web/20140102225926/http://www8.hp.com/us/en/products/server-software/product-detail.html?oid=5104018)
([HP SPP](https://web.archive.org/web/20140103153853/http://h17007.www1.hp.com/us/en/enterprise/servers/products/service_pack/spp/index.aspx)).

This iso file contains the firmware for all supported HP servers. The easiest
way is to boot from the ISO file and upgrade the server where it is running.
If you have many servers - it's better to use an automated way using PXEboot,
Cobbler and NFS.

I would like to share a few steps on how I did it in my environment.

Download the HP SPP and prepare the NFS:

```bash
yum install -y nfs-utils rpcbind

chkconfig nfs on

mkdir -p /data/hp/HP_Service_Pack_for_Proliant
chown -R nfsnobody:nfsnobody /data

cat > /etc/exports << EOF
/data                                   0.0.0.0/0.0.0.0(ro,no_root_squash,no_subtree_check,async,crossmnt,fsid=0)
EOF

cd /data/hp/ || exit
wget http://ftp.okhysing.is/hp/spp/2013-09/HP_Service_Pack_for_Proliant_2013.09.0-0_744345-001_spp_2013.09.0-SPP2013090.2013_0830.30.iso

ln -s HP_Service_Pack_for_Proliant_2013.09.0-0_744345-001_spp_2013.09.0-SPP2013090.2013_0830.30.iso HPSPP.iso
echo "/data/hp/HPSPP.iso /data/hp/HP_Service_Pack_for_Proliant iso9660 ro,loop,auto 0 0" >> /etc/fstab

mount /data/hp/HP_Service_Pack_for_Proliant
```

Now install and configure [Cobbler](https://www.cobblerd.org/) to boot the
HP SPP using PXE:

```bash
# Install EPEL
MAJOR_RELEASE=$(sed 's/.* \([0-9]*\)\.[0-9] .*/\1/' /etc/redhat-release)
cd /tmp/ || exit
lftp -e "mget /pub/linux/fedora/epel/6/x86_64/epel-release*.noarch.rpm; quit;" http://ftp.fi.muni.cz/
rpm -Uvh ./epel*"${MAJOR_RELEASE}"*.noarch.rpm

# Install Cobbler
yum install -y cobbler-web fence-agents git hardlink ipmitool dhcp

sed -i.orig 's/module = authn_denyall/module = authn_configfile/' /etc/cobbler/modules.conf
HTDIGEST_HASH=$(printf admin:Cobbler:admin123 | md5sum -)
echo "admin:Cobbler:${HTDIGEST_HASH:0:32}" >> /etc/cobbler/users.digest

PASSWORD_HASH=$(openssl passwd -1 'admin123')
sed -i.orig "s/^\(anamon_enabled:\).*/\1 1/;s@^\(default_password_crypted:\).*@\1 \"$PASSWORD_HASH\"@;s/^\(manage_dhcp:\).*/\1 1/;s/^\(next_server:\).*/\1 10.29.49.7/;s/^\(pxe_just_once:\).*/\1 1/;s/^\(server:\).*/\1 10.29.49.7/;s/^\(scm_track_enabled:\).*/\1 1/;s/^power_management_default_type:.*/power_management_default_type: 'ilo'/" /etc/cobbler/settings

# Change DHCPd template
sed -i.orig 's/192.168.1.0/10.29.49.0/;s/192.168.1.5;/10.29.49.1;/;s/192.168.1.1;/10.226.32.44;/;s/255.255.255.0/255.255.255.128/;s/192.168.1.100 192.168.1.254/10.29.49.100 10.29.49.126/;' /etc/cobbler/dhcp.template

# Configure DHCPd
sed -i.orig 's/^DHCPDARGS=.*/DHCPDARGS="eth0"/' /etc/sysconfig/dhcpd

SPP_INITRD=$(ls /data/hp/HP_Service_Pack_for_Proliant/pxe/spp*/initrd.img)
SPP_KERNEL=$(ls /data/hp/HP_Service_Pack_for_Proliant/pxe/spp*/vmlinuz)
cobbler distro add --name=hp-sos --arch=i386 --kernel="$SPP_KERNEL" --initrd="$SPP_INITRD" \
  --kopts '!kssendmac !ksdevice !lang !text rw root=/dev/ram0 init=/bin/init loglevel=3 splash=verbose showopts media=net iso1=nfs://10.29.49.7/data/hp/HPSPP.iso iso1mnt=/mnt/bootdevice iso1opts=nolock,timeo=600 d3bug'

cobbler profile add --name="Firmware_Upgrade-Automatic" --distro=hp-sos --kopts="TYPE=AUTOMATIC AUTOPOWEROFFONSUCCESS=no AUTOREBOOTONSUCCESS=yes" --kickstart=""
cobbler profile add --name="Firmware_Upgrade-Interactive" --distro=hp-sos --kopts="TYPE=MANUAL AUTOPOWEROFFONSUCCESS=no" --kickstart=""
cobbler profile add --name="Firmware_Upgrade-Automatic_POWEROFF" --distro=hp-sos --kopts="TYPE=AUTOMATIC" --kickstart=""

service cobblerd restart
chkconfig cobblerd on
service httpd restart
chkconfig httpd on
chkconfig dhcpd on
service xinetd restart

cobbler sync

# Just to be sure
chkconfig iptables off
service iptables stop
```

Once the tftp, NFS, dhcp is ready you can try to "Boot from Network" one of the
servers. If the networking is working fine you should at least get the IP from
the DHCP server and the main "Cobbler blue" menu.

You can see the full video recorded during "test" firmware upgrade below:

{% include embed/youtube.html id='KwiPs225agc' %}

(some parts of the video are accelerated)

Enjoy :-)
