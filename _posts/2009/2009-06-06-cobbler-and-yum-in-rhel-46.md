---
title: Cobbler and yum in RHEL 4.6
author: Petr Ruzicka
date: 2009-06-06
description: ""
categories: [Linux, RHEL]
tags: [bash, perl, Apache, Cobbler, PXE, yum, serial]
---

> <https://linux-old.xvx.cz/2009/06/cobbler-and-yum-in-rhel-46/>
{: .prompt-info }

Look at small how-to install [cobbler](https://fedorahosted.org/cobbler/)
with yum on [RHEL 4.6](https://www.redhat.com/rhel/) from scratch.

Install RHEL 4.6 or [CentOS](https://www.centos.org/) 4.6 with default
partitioning and custom installation (unselect all possible packages during
installation procedure). Disable firewall and SELinux.

- Enable DVD repository by changing the line in
  `/etc/yum.repos.d/CentOS-Media.repo`:

  ```ini
  enabled=1
  ```

- Install yum:

  ```bash
  mount /media/cdrom
  ```

- Download packages and install them:

  ```bash
  mkdir /var/tmp/cobbler-4.6
  cd /var/tmp/cobbler-4.6 || exit
  ```

  ```bash
  rpm -i ./python-elementtree-1.2.6-5.el4.centos.x86_64.rpm \
    ./python-urlgrabber-2.9.8-2.noarch.rpm ./sqlite-3.3.6-2.x86_64.rpm \
    ./python-sqlite-1.1.7-1.2.1.x86_64.rpm \
    ./yum-metadata-parser-1.0-8.el4.centos.x86_64.rpm \
    ./centos-yumconf-4-4.5.noarch.rpm \
    ./yum-2.4.3-4.el4.centos.noarch.rpm \
    ./createrepo-0.4.4-2.noarch.rpm
  ```

  ```bash
  yum clean all
  mkdir /var/tmp/rhel4_repo/
  ln -s /media/cdrom/RedHat/RPMS/ /var/tmp/rhel4_repo/RPMS
  createrepo /var/tmp/rhel4_repo/
  cat > /etc/yum.repos.d/RHEL-4.6-Media.repo << +
  [rhel4-media]
  name=RHEL4 - Media
  baseurl=file:///var/tmp/rhel4_repo/
  gpgcheck=0
  enabled=1
  +

  createrepo /var/tmp/cobbler-4.6/
  cat >> /etc/yum.repos.d/my.repo << +
  [my-repo]
  name=My Repository
  baseurl=file:///var/tmp/cobbler-4.6/
  gpgcheck=0
  enabled=1
  +
  ```

- Install necessary software from DVD:

  ```bash
  mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.orig

  yum -y install wget mc
  yum -y install httpd tftp-server mod_python python-devel createrepo rsync mkisofs
  yum -y install perl-Digest-SHA1 perl-Digest-HMAC perl-Socket6 perl-Time-HiRes sysstat perl-libwww-perl
  yum -y install libart_lgpl freetype libpng
  yum -y install logrotate perl-DateManip
  yum -y install cman
  yum -y install dhcp bind
  yum -y install memtest86+

  yum -y install cobbler
  yum -y install munin munin-node php-ldap
  chkconfig munin-node on
  yum -y install yum-utils
  yum -y install syslinux
  ```

- Disable firewall (just for sure):

  ```bash
  chkconfig --level 2345 iptables off
  service iptables stop
  ```

- Change line in `/etc/cobbler/settings` to match the IP of the server:

  ```yaml
  default_password_crypted: "$1$pH3........0B2HB/"
  default_name_servers: [192.168.0.129]
  manage_dhcp: 1
  manage_dns: 1
  manage_forward_zones: [my.domain.cz]
  manage_reverse_zones: [192.168.0]
  next_server: 192.168.0.129
  pxe_just_once: 1
  server: 192.168.0.129
  register_new_installs: 0
  xmlrpc_rw_enable: 1
  ```

- Start cobbler and apache daemon:

  ```bash
  /etc/init.d/cobblerd start
  /etc/init.d/httpd start
  chkconfig httpd on
  ```

- Change 'disable' to 'no' in `/etc/xinetd.d/tftp`:

  ```ini
  disable                 = yes
  ```

## Cobbler/DHCPd/bind configuration

- Change listening interface for dhcpd in `/etc/sysconfig/dhcpd`:

  ```ini
  DHCPDARGS=eth0;
  ```

- Modify file `/etc/cobbler/dhcp.template` according your needs:

  ```text
  subnet 192.168.0.0 netmask 255.255.255.0 {
       option routers             10.226.23.1;
       option domain-name         "my.domain.cz";
       option domain-name-servers 192.168.0.129;
       option subnet-mask         255.255.255.0;
       range dynamic-bootp        192.168.0.200 192.168.0.254;
       filename                   "/pxelinux.0";
       default-lease-time         21600;
       max-lease-time             43200;
       next-server                $next_server;
  }
  ```

- Modify `/etc/cobbler/named.template` like:

  ```text
  options {
  ...
  #          listen-on port 53 { 127.0.0.1; };
  ...
  #          allow-query     { localhost; };
             forwarders { 10.226.32.44; };
  ...
  };
  ```

  ```bash
  cobbler sync
  service xinetd restart
  chkconfig dhcpd on
  chkconfig named on
  ```

- Now you should run:

  ```bash
  cobbler check
  ```

- and see something like that:

  ```console
  [root@c2virtud tmp]# cobbler check
  No setup problems found
  Manual review and editing of /var/lib/cobbler/settings is recommended to tailor cobbler to your particular configuration.
  ```

## Cobbler repository+ installation

  ```bash
  cobbler import --name=RHEL4.6-x86_64-AS --mirror=/media/cdrom/
  cobbler repo add --mirror=/var/tmp/cobbler-4.6/ --name=my-repo
  ```

  ```bash
  cobbler reposync
  cobbler image add --name=Memtest86+-1.26 --file=/tftpboot/memtest86+-1.26 --image-type=direct
  cobbler profile copy --name=RHEL4.6-AS-x86_64 --newname=NGP_RHEL4.6-AS-x86_64
  cobbler profile copy --name=rescue-RHEL4.6-AS-x86_64 --newname=NGP_rescue-RHEL4.6-AS-x86_64
  cobbler profile edit --name=NGP_RHEL4.6-AS-x86_64 --repos="my-repo"
  cobbler profile edit --name=NGP_rescue-RHEL4.6-AS-x86_64 --repos="my-repo"
  cobbler sync
  ```

- Edit `/etc/yum.repos.d/RHEL-4.6-Media.repo` and change one line like:

  ```ini
  baseurl=file:///var/www/cobbler/ks_mirror/RHEL4.6-x86_64-AS/RedHat
  ```

- Then run:

  ```bash
  yum clean all
  ```

### PXE configuration

- Make this the first line of `/etc/cobbler/pxe/pxedefault.template`,
  `pxeprofile.template`, `pxesystem.template` to enable serial connection:

  ```text
  SERIAL 0 115200
  ```

### Cobbler WebUI

- Set root password for web access:

  ```bash
  htdigest /etc/cobbler/users.digest "Cobbler" root
  ```

- Change line in `/etc/cobbler/modules.conf`:

  ```ini
  module = authn_configfile
  ```

  ```bash
  service cobblerd restart
  service httpd restart
  ```

## Cobbler host specification

```bash
cobbler system add --comment="c3virt01ce01 machine" --name=c3virt01ce01 --hostname=c3virt01ce01 --netboot-enabled=1 --profile=NGP_RHEL4.6-AS-x86_64 --name-servers=192.168.0.129 --static=0 --kickstart=/var/lib/cobbler/kickstarts/legacy.ks
cobbler system edit --name c3virt01ce01 --interface=eth0 --mac=00:0c:29:68:78:96 --ip=192.168.0.10 --netmask=255.255.255.0 --static=1 --dns-name=c3virt01ce01.my.domain.cz
cobbler system edit --name c3virt01ce01 --interface=eth1 --mac=00:0c:29:68:78:b4 --ip=192.168.1.10 --netmask=255.255.255.0 --static=1
cobbler system edit --name c3virt01ce01 --interface=eth2 --mac=00:0c:29:68:78:aa --ip=192.168.2.10 --netmask=255.255.255.0 --static=1
cobbler system edit --name c3virt01ce01 --interface=eth3 --mac=00:0c:29:68:78:be --static=0
```

```bash
cobbler sync
```

Hope it will be possible to use PXE boot to install machines.
