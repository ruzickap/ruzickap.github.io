---
title: VMware vCenter Server 5.x Appliance installation and configuration using ssh command line
author: Petr Ruzicka
date: 2014-09-27
description: VMware vCenter Server 5.x Appliance installation and configuration using ssh command line
categories: [Linux]
tags: [appliance, ovftool, vmware, command line, vcenter, ssh]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2014/09/vmware-vcenter-server-5x-appliance.html)
{: .prompt-info }

Here you can find some notes about installing VMware vCenter Appliance from
command line directly from ESXi using [OVF Tool](https://web.archive.org/web/20140715092309/https://www.vmware.com/support/developer/ovf/).

![image](/assets/img/posts/2014/2014-09-27-vmware-vcenter-server-5x-appliance-instalation-and-configuration-using-ssh-command-line/vcenter.avif)

Install the OVF tools first. Details can be found here:
[https://www.virtuallyghetto.com/2012/05/how-to-deploy-ovfova-in-esxi-shell.html](https://www.virtuallyghetto.com/2012/05/how-to-deploy-ovfova-in-esxi-shell.html).

```bash
#Download OVF tools
wget -q ftp://ftp.example.com/software/vmware/installation_scripts/vmware-ovftool.tar.gz -O /vmfs/volumes/My_Datastore/vmware-ovftool.tar.gz

# Extract ovftool content to /vmfs/volumes/My_Datastore
tar -xzf /vmfs/volumes/My_Datastore/vmware-ovftool.tar.gz -C /vmfs/volumes/My_Datastore/
rm /vmfs/volumes/My_Datastore/vmware-ovftool.tar.gz

# Modify the ovftool script to work on ESXi
sed -i 's@^#!/bin/bash@#!/bin/sh@' /vmfs/volumes/My_Datastore/vmware-ovftool/ovftool
```

Provision VMware vCenter Server 5.x Appliance using OVFtool directly to ESXi and
then configure it via SSH:

```bash
# Deploy OVF from remote HTTP source
/vmfs/volumes/My_Datastore/vmware-ovftool/ovftool --diskMode=thin --datastore=My_Datastore --noSSLVerify --acceptAllEulas --skipManifestCheck "--net:Network 1=VMware Management Network" --prop:vami.ip0.VMware_vCenter_Server_Appliance=10.29.49.99 --prop:vami.netmask0.VMware_vCenter_Server_Appliance=255.255.255.128 --prop:vami.gateway.VMware_vCenter_Server_Appliance=10.29.49.1 --prop:vami.DNS.VMware_vCenter_Server_Appliance=10.1.1.44 --prop:vami.hostname=vcenter.example.com "ftp://ftp.example.com/software/vmware/VMware-vCenter-Server-Appliance-5.5.0.10000-1624811_OVF10.ova" "vi://root:mypassword@127.0.0.1"

echo "Accepting EULA ..."
/usr/sbin/vpxd_servicecfg eula accept
echo "Configuring Embedded DB ..."
/usr/sbin/vpxd_servicecfg db write embedded
echo "Configuring SSO..."
/usr/sbin/vpxd_servicecfg sso write embedded
echo "Starting VCSA ..."
/usr/sbin/vpxd_servicecfg service start

echo "Configure NTP"
/usr/sbin/vpxd_servicecfg timesync write ntp ntp.example.com
echo "Set Proxy Server"
/opt/vmware/share/vami/vami_set_proxy px01.example.com 3128

# Password change
echo rootpassword | passwd --stdin

# Add user admin
useradd admin
echo admin123 | passwd --stdin admin
chage -M -1 -E -1 admin

# If you wish to completely disable account password expiry, you can do so by running the following command:
chage -M -1 -E -1 root

echo "Configure Network Settings"
/opt/vmware/share/vami/vami_set_dns 10.0.0.44 10.0.0.45
/opt/vmware/share/vami/vami_set_hostname vcenter.example.com
/opt/vmware/share/vami/vami_set_timezone_cmd Europe/Prague

# Regenerate all certificates next reboot
echo only-once > /etc/vmware-vpx/ssl/allow_regeneration

# Add SSH key
mkdir /root/.ssh
wget ftp://ftp.example.com/ssh_keys/id_dsa.pub -O /root/.ssh/authorized_keys
chmod 755 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

# Install SuSe repositories
zypper --gpg-auto-import-keys ar http://download.opensuse.org/distribution/11.1/repo/oss/ 11.1
zypper --gpg-auto-import-keys ar http://download.opensuse.org/update/11.1/ Update-11.1
rm /etc/zypp/repos.d/Update-11.1.repo
zypper --no-gpg-checks refresh

# Install MC :-)
zypper install -y mc

# Disable mouse support in MC
sed -i 's@/usr/bin/mc@/usr/bin/mc --nomouse@' /usr/share/mc/bin/mc-wrapper.sh

( sleep 10; reboot ) &

# Set static IP
/opt/vmware/share/vami/vami_set_network eth0 STATICV4 10.0.0.99 255.255.255.128 10.0.0.1
```

Then you can automatically register the ESXi servers to the vCenter using
"[joinvCenter.py](https://github.com/lamw/vghetto-scripts/blob/master/python/joinvCenter.py)".
Details here [https://www.virtuallyghetto.com/2011/03/how-to-automatically-add-esxi-host-to.html](https://www.virtuallyghetto.com/2011/03/how-to-automatically-add-esxi-host-to.html).

Thank you guys from the [virtuallyGhetto](https://www.virtuallyghetto.com/) for
their awesome blog full of great "VMware ideas".
