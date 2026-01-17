---
title: Installation F5 BIGIP Virtual Edition to RHEL7
author: Petr Ruzicka
date: 2014-12-23
description: Installation F5 BIGIP Virtual Edition to RHEL7
categories: [Virtualization, Networking]
tags: [nmcli, LTM, Local Traffic Manager, iapp, bond, bigip, BIG-IP, vlan, bridge]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2014/12/installtion-f5-bigip-virtual-edition-to.html)
{: .prompt-info }

The physical hardware running the F5 BIG-IP Local Traffic Manager load balancing
software is powerful, but also quite expensive. For a lab environment you do
not need to buy new hardware, but you can get the
[F5 BIG-IP Local Traffic Manager Virtual Edition](https://www.f5.com/trial/big-ip-ltm-virtual-edition.php)
and install it as virtual machine.

That is the way I would like to describe here. I had one spare
[HP ProLiant DL380p Gen8](https://web.archive.org/web/20150207155049/http://www8.hp.com/us/en/products/proliant-servers/product-detail.html?oid=5177957)
so [RHEL7](https://en.wikipedia.org/wiki/Red_Hat_Enterprise_Linux#RHEL_7)
virtualization ([KVM](https://www.linux-kvm.org/)) was the first choice.

In short I had to deal with bonding (two cables going to the 2 separate
switches), trunk containing 3 vlans, bridges and finally with the F5
configuration itself.

![F5 BIG-IP Virtual Edition network diagram with KVM](https://raw.githubusercontent.com/ruzickap/linux.xvx.cz/refs/heads/gh-pages/pics/f5_kvm/f5_kvm.svg)

Here are some notes about it...

## RHEL7 Configuration

Start with network:

```bash
#Set hostname
hostnamectl set-hostname lb01-server.example.com

#Remove all network configuration
nmcli con del eno{1,2,3,4}

#Configure bonding
nmcli con add type bond con-name bond0 ifname bond0 mode active-backup
nmcli con add type bond-slave con-name eno1 ifname eno1 master bond0
nmcli con add type bond-slave con-name eno2 ifname eno2 master bond0

#Configure bridging, IPs, DNS,
nmcli con add type bridge con-name br1169 ifname br1169 ip4 10.0.0.226/24 gw4 10.0.0.1
nmcli con mod br1169 ipv4.dns "10.0.0.141 10.0.0.142"
nmcli con mod br1169 ipv4.dns-search "example.com"

#Configure VLANs
nmcli con add type bridge-slave con-name bond0.1169 ifname bond0.1169 master br1169
nmcli con add type bridge-slave con-name bond0.1170 ifname bond0.1170 master br1170
nmcli con add type bridge-slave con-name bond0.1261 ifname bond0.1261 master br1261

#NetworkManager can not bridge VLANs in RHEL7 - so here is a workaround:
sed -i 's/^TYPE=.*/TYPE=Vlan/' /etc/sysconfig/network-scripts/ifcfg-bond0.{1170,1261,1169}
echo "VLAN=yes" >> /etc/sysconfig/network-scripts/ifcfg-bond0.1169
echo "VLAN=yes" >> /etc/sysconfig/network-scripts/ifcfg-bond0.1170
echo "VLAN=yes" >> /etc/sysconfig/network-scripts/ifcfg-bond0.1261

reboot
```

Do some basic RHEL7 customizations + [HP SPP](https://web.archive.org/web/20141231041952/http://h17007.www1.hp.com/us/en/enterprise/servers/products/service_pack/spp/index.aspx)
installation:

```bash
umount /home
sed -i '/\/home/d' /etc/fstab
lvremove -f /dev/mapper/rhel-home
lvextend --resizefs -l +100%FREE /dev/mapper/rhel-root

curl http://10.0.0.141:6809/fusion/rhel-server-7.0-x86_64-dvd.iso > /var/tmp/rhel-server-7.0-x86_64-dvd.iso

mkdir /mnt/iso
echo "/var/tmp/rhel-server-7.0-x86_64-dvd.iso /mnt/iso iso9660 loop,ro 0 0" >> /etc/fstab
mount /mnt/iso

cp /mnt/iso/media.repo /etc/yum.repos.d/
chmod u+w /etc/yum.repos.d/media.repo

cat >> /etc/yum.repos.d/media.repo << EOF
enabled=1
baseurl=file:///mnt/iso
EOF

yum install -y http://ftp.fi.muni.cz/pub/linux/fedora/epel/7/x86_64/e/epel-release-7-2.noarch.rpm

yum install -y bash-completion bind-utils bridge-utils dstat htop httpd ipmitool iotop lftp lsof mailx man mc mlocate mutt net-snmp net-snmp-utils net-tools nmap ntp ntpdate openssh-clients postfix rsync sos smartmontools screen strace sysstat telnet tcpdump traceroute unzip vim wget wireshark xz yum-utils

sed -i 's@^\*/10 \*@\*/1 \*@' /etc/cron.d/sysstat
echo "PS1='\[\033[01;31m\]\h\[\033[01;34m\] \w #\[\033[00m\] '" >> /root/.bashrc
echo -e "\nalias sar='LANG=C sar'" >> /etc/bashrc

cat >> /etc/screenrc << EOF
defscrollback 10000
startup_message off
termcapinfo xterm ti@:te@
hardstatus alwayslastline '%{= kG}[ %{G}%H %{g}][%= %{= kw}%?%-Lw%?%{r}(%{W}%n*%f%t%?(%u)%?%{r})%{w}%?%+Lw%?%?%= %{g}][%{B} %d/%m %{W}%c %{g}]'
vbell off
EOF

IP=$(ip a s br1169 | sed -n 's@[[:space:]]*inet \([^/]*\)/.*@\1@p')
echo -e "${IP}\t\t$HOSTNAME" >> /etc/hosts

sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/;s/quiet//;s/rhgb//' /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg

sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

chkconfig firewalld off
#chkconfig rhsmcertd off
#chkconfig rhnsd off
#chmod a-x /etc/cron.daily/rhsmd

systemctl disable avahi-daemon.socket avahi-daemon.service
systemctl disable iprdump iprinit iprupdate
chkconfig ntpd on

sed -i.orig "s/^\(SYNC_HWCLOCK\)=no/\1=yes/" /etc/sysconfig/ntpdate

chkconfig snmpd on

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

test -f /usr/libexec/mc/mc-wrapper.sh && sed -i 's/mc-wrapper.sh/mc-wrapper.sh --nomouse/' /etc/profile.d/mc.sh

cat > /etc/yum.repos.d/hp.repo << \EOF
[HP-SPP]
name=HP Software Delivery Repository for SPP $releasever - $basearch
baseurl=http://downloads.linux.hp.com/SDR/repo/spp/RHEL/$releasever/$basearch/current/
enabled=1
gpgcheck=0
EOF

yum install -y hponcfg hp-snmp-agents hp-ams hpssacli hp-smh-templates hpsmh
hpsnmpconfig --a --rws my_write --ros my_read --rwmips 127.0.0.1 my_write --romips 127.0.0.1 my_read --tcs private --tdips 127.0.0.1 public --sci $HOSTNAME --sli My_Servers
/opt/hp/hpsmh/sbin/smhconfig --autostart=true

postconf -e 'relayhost = yum.example.com'
postconf -e 'inet_interfaces = all'

cat >> /etc/aliases << EOF
root:           petr.ruzicka@gmail.com
EOF
newaliases
```

Configure the [libvirt](https://libvirt.org/) including networking and virtual
machine running F5 BIG-IP LTM VE:

```bash
yum install -y qemu-kvm virt-install "@Virtualization Platform"
tuned-adm profile virtual-host

systemctl enable libvirt-guests.service
service libvirtd start
virsh net-autostart --disable default

for VLAN in 1169 1170 1261; do
cat > /tmp/br$VLAN.xml << EOF
<network>
  <name>br$VLAN</name>
  <forward mode='bridge'/>
  <bridge name='br$VLAN'/>
</network>
EOF

virsh net-define /tmp/br$VLAN.xml
virsh net-autostart br$VLAN
done

cat >> /etc/libvirt/libvirtd.conf << EOF
listen_tcp = 1
listen_tls = 0
log_level = 2
log_outputs="2:syslog:libvirtd"
EOF

cat >> /etc/sysconfig/libvirt-guests << EOF

ON_SHUTDOWN=shutdown
SHUTDOWN_TIMEOUT=100
EOF

echo 'LIBVIRTD_ARGS="--listen"' >> /etc/sysconfig/libvirtd

wget http://10.0.0.141:6809/fusion/BIGIP-11.6.0.0.0.401.ALL.qcow2.zip -P /var/tmp/
unzip -d /var/lib/libvirt/images/ /var/tmp/BIGIP-11.6.0.0.0.401.ALL.qcow2.zip

reboot

# http://support.f5.com/kb/en-us/products/big-ip_ltm/manuals/product/bigip-ve-kvm-setup-11-3-0/2.html#conceptid
virt-install \
  --name=F5-BIGIP \
  --description="BIG-IP Local Traffic Manager (LTM) Virtual Edition (VE)" \
  --disk path=/var/lib/libvirt/images/BIGIP-11.6.0.0.0.401.qcow2,bus=virtio,format=qcow2 \
  --disk path=/var/lib/libvirt/images/BIGIP-11.6.0.0.0.401.DATASTOR.ALL.qcow2,bus=virtio,format=qcow2 \
  --network=bridge=br1261,model=virtio \
  --network=bridge=br1169,model=virtio \
  --network=bridge=br1170,model=virtio \
  --network=type=direct,source=eno3,source_mode=bridge,model=virtio \
  --network=type=direct,source=eno4,source_mode=bridge,model=virtio \
  --graphics vnc,password=admin123,listen=0.0.0.0,port=5900 \
  --serial tcp,host=:2222,mode=bind,protocol=telnet \
  --vcpus=4 --cpu host --ram=12288 \
  --os-type=linux \
  --os-variant=rhel6 \
  --import --autostart --noautoconsole
```

## BIGIP F5 Virtual Edition

Initial configuration:

```bash
#(root / default)

tmsh modify sys global-settings mgmt-dhcp disabled
tmsh create sys management-ip 10.0.0.224/255.255.255.0
tmsh create sys management-route default gateway 10.0.0.1
#(or you can use "config" command - to speed it up)

#DNS
tmsh modify sys dns name-servers add { 10.0.0.141 10.0.0.142 }
tmsh modify sys dns search add { cloud.example.com }
#Hostname
tmsh modify sys glob hostname lb01.cloud.example.com
#NTP
tmsh modify sys ntp servers add { 0.rhel.pool.ntp.org 1.rhel.pool.ntp.org }
tmsh modify sys ntp timezone "UTC"
#Session timeout
tmsh modify sys sshd inactivity-timeout 120000
tmsh modify sys http auth-pam-idle-timeout 120000
#SNMP allow from "all"
tmsh modify sys snmp allowed-addresses add { 10.0.0.0/8 }
#SNMP traps
tmsh modify /sys snmp traps add { my_trap_destination { host monitor.cloud.example.com community public version 2c } }
# Network configuration...
tmsh create net vlan External interfaces add { 1.2 }
tmsh create net vlan Internal interfaces add { 1.1 }
#SMTP
tmsh create sys smtp-server yum.cloud.example.com { from-address root@lb01.cloud.example.com local-host-name lb01.cloud.example.com smtp-server-host-name yum.cloud.example.com }
tmsh create net self 10.0.0.224/24 vlan Internal allow-service all
tmsh create net self 10.0.1.224/24 vlan External allow-service all
#https://support.f5.com/kb/en-us/solutions/public/13000/100/sol13180.html
tmsh modify /sys outbound-smtp mailhub yum.cloud.example.com:25
#Send email when there are some problems with monitoring nodes "up/down"
cat > /config/user_alert.conf << EOF
alert Monitor_Status "monitor status" {
        email toaddress="petr.ruzicka@example.com"
        fromaddress="root"
        body="Check the Server status: https://10.0.0.224"
}
EOF

echo 'ssh-dss AX.... ....UQ= admin' >> /root/.ssh/authorized_keys

cat > /root/.ssh/id_dsa << EOF
-----BEGIN DSA PRIVATE KEY-----
...
...
-----END DSA PRIVATE KEY-----
EOF

tmsh modify auth password admin # my_secret_password
tmsh modify auth user admin shell bash
mkdir /home/admin/.ssh && chmod 700 /home/admin/.ssh
cp -L /root/.ssh/authorized_keys /home/admin/.ssh/
tmsh modify auth password root  # my_secret_password2

tmsh install /sys license registration-key ZXXXX-XXXXX-XXXXX-XXXXX-XXXXXXL

curl http://10.0.0.141/Hotfix-BIGIP-11.6.0.1.0.403-HF1.iso > /shared/images/Hotfix-BIGIP-11.6.0.1.0.403-HF1.iso
scp 10.0.0.226:/var/tmp/BIGIP-11.6.0.0.0.401.iso /shared/images/

tmsh install sys software image BIGIP-11.6.0.0.0.401.iso volume HD1.2

tmsh install sys software hotfix Hotfix-BIGIP-11.6.0.1.0.403-HF1.iso volume HD1.2
tmsh show sys software status
tmsh reboot volume HD1.2
mount -o rw,remount /usr
rpm -Uvh --nodeps \
http://vault.centos.org/5.8/os/i386/CentOS/yum-3.2.22-39.el5.centos.noarch.rpm \
http://vault.centos.org/5.8/os/i386/CentOS/python-elementtree-1.2.6-5.i386.rpm \
http://vault.centos.org/5.8/os/i386/CentOS/python-iniparse-0.2.3-4.el5.noarch.rpm \
http://vault.centos.org/5.8/os/i386/CentOS/python-sqlite-1.1.7-1.2.1.i386.rpm \
http://vault.centos.org/5.8/updates/i386/RPMS/rpm-python-4.4.2.3-28.el5_8.i386.rpm \
http://vault.centos.org/5.8/os/i386/CentOS/python-urlgrabber-3.1.0-6.el5.noarch.rpm \
http://vault.centos.org/5.8/os/i386/CentOS/yum-fastestmirror-1.1.16-21.el5.centos.noarch.rpm \
http://vault.centos.org/5.8/os/i386/CentOS/yum-metadata-parser-1.1.2-3.el5.centos.i386.rpm

cat > /etc/yum.repos.d/CentOS-Base.repo << \EOF
[base]
name=CentOS-5 - Base
baseurl=http://mirror.centos.org/centos/5/os/i386/
gpgcheck=0

[updates]
name=CentOS-5 - Updates
baseurl=http://mirror.centos.org/centos/5/updates/i386/
gpgcheck=0
EOF

yum install -y mc screen

cat >> /etc/screenrc << EOF
defscrollback 10000
startup_message off
termcapinfo xterm ti@:te@
hardstatus alwayslastline '%{= kG}[ %{G}%H %{g}][%= %{= kw}%?%-Lw%?%{r}(%{W}%n*%f%t%?(%u)%?%{r})%{w}%?%+Lw%?%?%= %{g}][%{B} %d/%m %{W}%c %{g}]'
vbell off
EOF

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
sed -i.orig 's/mc-wrapper.sh/mc-wrapper.sh --nomouse/' /etc/profile.d/mc.sh

#Disable the GUI Wizard
tmsh modify sys global-settings gui-setup disabled

#SSL certificate
SUBJ="
C=CZ
ST=Czech Republic
O=Example, Inc.
localityName=Brno
commonName=cloud.example.com Certificate Authority
"
openssl req -x509 -nodes -subj "$(echo -n "$SUBJ" | tr "\n" "/")" -newkey rsa:2048 -keyout /config/ssl/ssl.key/cloud.example.com_self-signed_2014.key -out /config/ssl/ssl.crt/cloud.example.com_self-signed_2014.crt -days 3650

tmsh install /sys crypto key cloud.example.com_self-signed_2014.key from-local-file /config/ssl/ssl.key/cloud.example.com_self-signed_2014.key
tmsh install /sys crypto cert cloud.example.com_self-signed_2014.crt from-local-file /config/ssl/ssl.crt/cloud.example.com_self-signed_2014.crt
```

### DNS VIP iApp

```bash
tmsh create sys application service dns-ext-vip1_53 { \
    description "DNS VIP - External - NS1 53" \
    strict-updates disabled \
    tables add { \
        vs_pool__members { \
            column-names { addr port conn_limit } \
            rows { \
                { row { 10.0.1.10 53 0 } } \
                { row { 10.0.1.20 53 0 } } \
            } \
        } \
    } \
    template f5.dns \
    variables add { \
        app_health__frequency { value 30 } \
        app_health__monitor { value \"/#create_new#\" } \
        app_health__record_type { value a } \
        app_health__recv { value \"\" } \
        vs_pool__pool_to_use { value \"/#create_new#\" } \
        app_health__send { value ns1.cloud.example.com } \
        vs_pool__vs_addr { value 10.0.1.16 } \
        vs_pool__vs_port { value 53 } \
    } \
}

tmsh modify ltm virtual dns-ext-vip1_53.app/dns-ext-vip1_53_dns_tcp description "DNS VIP - External - NS1 TCP 53"
tmsh modify ltm virtual dns-ext-vip1_53.app/dns-ext-vip1_53_dns_udp description "DNS VIP - External - NS1 UDP 53"
tmsh modify ltm pool dns-ext-vip1_53.app/dns-ext-vip1_53_tcp_pool description "DNS VIP - External - NS1 TCP 53" members modify { 10.0.1.10:domain { description "Public DNS Master" } 10.0.1.20:domain { description "Public DNS Slave" } }
tmsh modify ltm pool dns-ext-vip1_53.app/dns-ext-vip1_53_udp_pool description "DNS VIP - External - NS1 UDP 53" members modify { 10.0.1.10:domain { description "Public DNS Master" } 10.0.1.20:domain { description "Public DNS Slave" } }

tmsh create sys application service dns-ext-vip2_53 { \
    description "DNS VIP - External - NS2 53" \
    strict-updates disabled \
    tables add { \
        vs_pool__members { \
            column-names { addr port conn_limit } \
            rows { \
                { row { 10.0.1.10 53 0 } } \
                { row { 10.0.1.20 53 0 } } \
            } \
        } \
    } \
    template f5.dns \
    variables add { \
        app_health__frequency { value 30 } \
        app_health__monitor { value \"/#create_new#\" } \
        app_health__record_type { value a } \
        app_health__recv { value \"\" } \
        vs_pool__pool_to_use { value \"/#create_new#\" } \
        app_health__send { value ns2.cloud.example.com } \
        vs_pool__vs_addr { value 10.0.1.17 } \
        vs_pool__vs_port { value 53 } \
    } \
}

tmsh modify ltm virtual dns-ext-vip2_53.app/dns-ext-vip2_53_dns_tcp description "DNS VIP - External - NS2 TCP 53"
tmsh modify ltm virtual dns-ext-vip2_53.app/dns-ext-vip2_53_dns_udp description "DNS VIP - External - NS2 UDP 53"
tmsh modify ltm pool dns-ext-vip2_53.app/dns-ext-vip2_53_tcp_pool description "DNS VIP - External - NS2 TCP 53" members modify { 10.0.1.10:domain { description "Public DNS Master" } 10.0.1.20:domain { description "Public DNS Slave" } }
tmsh modify ltm pool dns-ext-vip2_53.app/dns-ext-vip2_53_udp_pool description "DNS VIP - External - NS2 UDP 53" members modify { 10.0.1.10:domain { description "Public DNS Master" } 10.0.1.20:domain { description "Public DNS Slave" } }
tmsh modify ltm node 10.0.1.10 description "Public DNS Master"
tmsh modify ltm node 10.0.1.20 description "Public DNS Slave"
```

### LDAP VIP iApp

```bash
tmsh create sys application service ds-vip_389 { \
    description "Directory Server VIP 389" \
    strict-updates disabled \
    lists add { irules__irules { } } \
    tables add { \
        vs_pool__pool_members { \
            column-names { addr port conn_limit } \
            rows { \
                { row { 10.0.0.150 389 0 } } \
                { row { 10.0.0.151 389 0 } } \
            } \
        } \
    } \
    template f5.ldap \
    variables add { \
        app_health__account { value "cn=directory manager,o=cloud.example.com" } \
        app_health__frequency { value 30 } \
        app_health__monitor { value \"/#create_new#\" } \
        app_health__monitor_password { value my_ldap_password } \
        app_health__search_level { value o=cloud.example.com } \
        app_health__search_query { value dc=test } \
        client_opt__tcp_opt { value \"/#lan#\" } \
        server_opt__tcp_opt { value \"/#lan#\" } \
        ssl_encryption_questions__advanced_mode { value yes } \
        vs_pool__bigip_route { value yes } \
        vs_pool__lb_method { value least-connections-member } \
        vs_pool__persistence { value \"/#default#\" } \
        vs_pool__pool_to_use { value \"/#create_new#\" } \
        vs_pool__vs_addr { value 10.0.0.203 } \
        vs_pool__vs_port { value 389 } \
    } \
}

tmsh modify ltm virtual ds-vip_389.app/ds-vip_389_vs description "Directory Server VIP 389 tcp"

tmsh modify ltm pool ds-vip_389.app/ds-vip_389_pool description "Directory Server VIP 389" members modify { 10.0.0.150:ldap { description "Directory server - primary" } 10.0.0.151:ldap { description "Directory server - secondary" } }

tmsh modify ltm node 10.0.0.150 description "Directory server - primary"
tmsh modify ltm node 10.0.0.151 description "Directory server - secondary"
```

### HTTPS VIP iApp

```bash
tmsh create sys application service https-vip_443 { \
    description "HTTPS Server VIP 443" \
    strict-updates disabled \
    tables add { \
        pool__hosts { \
            column-names { name } \
            rows { { row { config.cloud.example.com } } } \
        } \
        pool__members { \
            column-names { addr port_secure connection_limit } \
            rows { \
                { row { 10.0.1.140 443 0 } } \
                { row { 10.0.1.150 443 0 } } \
            } \
        } \
    } \
    template f5.http \
    variables add { \
        client__http_compression { value \"/#create_new#\" } \
        monitor__monitor { value \"/#create_new#\" } \
        monitor__response { value \"\" } \
        monitor__uri { value / } \
        net__client_mode { value wan } \
        net__server_mode { value lan } \
        pool__addr { value 10.0.1.94 } \
        pool__pool_to_use { value \"/#create_new#\" } \
        pool__port_secure { value 443 } \
        pool__port { value 443 } \
        ssl__mode { value client_ssl } \
        ssl__server_ssl_profile { value \"/#default#\" } \
        ssl__cert { value /Common/cloud.example.com_self-signed_2014.crt } \
        ssl__client_ssl_profile { value \"/#create_new#\" } \
        ssl__key { value /Common/cloud.example.com_self-signed_2014.key } \
    } \
}

tmsh modify ltm virtual https-vip_443.app/https-vip_443_vs description "HTTPS Server VIP"
tmsh modify ltm pool https-vip_443.app/https-vip_443_pool description "HTTPS Server VIP 443" members modify { 10.0.1.140:http { description "HTTPS Server 01" } 10.0.1.150:http { description "HTTPS Server 02" } }
tmsh modify ltm node 10.0.1.140 description "HTTPS Server 01"
tmsh modify ltm node 10.0.1.150 description "HTTPS Server 02"
```

That's all. I hope it will save some time.
