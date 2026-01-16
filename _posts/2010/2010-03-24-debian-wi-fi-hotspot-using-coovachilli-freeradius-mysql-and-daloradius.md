---
title: Debian Wi-Fi hotspot using CoovaChilli, FreeRadius, MySQL and daloRADIUS
author: Petr Ruzicka
date: 2010-03-24
categories: [Linux, Networking]
tags: [WiFi, hotspot, CoovaChilli, FreeRadius, MySQL, Apache]
---

I decided to create a
[hotspot](https://en.wikipedia.org/wiki/Hotspot_%28Wi-Fi%29) from my server to
allow others to connect to the Internet for free. I used "[Captive
portal](https://en.wikipedia.org/wiki/Captive_portal)" solution based on these
applications:

- [CoovaChilli](https://coova.org/CoovaChilli)
- [FreeRadius](https://freeradius.org/)
- [MySQL](https://www.mysql.com/)
- [daloRADIUS](https://daloradius.com/)

When somebody wants to connect to Internet using my wifi, the first page he can
see is the register/login page (whatever page he wants to visit).
After registration/login he is able to connect to Internet.

So let's see how I did it.

Let's have one server with two network interfaces - first `eth0` goes to
Internet, the second one `eth1` is the wifi for "unknown" clients.

![Embedded content](/assets/img/posts/2010/2010-03-24-debian-wi-fi-hotspot-using-coovachilli-freeradius-mysql-and-daloradius/hotspot.svg)

Install basic software:

```bash
aptitude install mysql-server phpmyadmin freeradius freeradius-utils freeradius-mysql apache2 php-pear php-db
a2enmod ssl
a2ensite default-ssl
service apache2 restart
cd /tmp && wget 'http://downloads.sourceforge.net/project/daloradius/daloradius/daloradius-0.9-8/daloradius-0.9-8.tar.gz'
tar xvzf daloradius-0.9-8.tar.gz
mv /tmp/daloradius-0.9-8 /var/www/daloradius
chown -R www-data:www-data /var/www/daloradius
cp -r /var/www/daloradius/contrib/chilli/portal2/* /var/www/
rm /var/www/index.html
```

Because my machine is 64 bit I need to build CoovaChilli package myself:

```bash
aptitude --assume-yes install dpkg-dev debhelper libssl-dev
cd /tmp
wget -c http://ap.coova.org/chilli/coova-chilli-1.2.2.tar.gz
tar xzf coova-chilli*.tar.gz
cd coova-chilli*
dpkg-buildpackage -rfakeroot
```

Install CoovaChilli:

```bash
cd ..
dpkg -i coova-chilli_*_amd64.deb
```

## Configure FreeRadius

Change `/etc/freeradius/clients.conf`:

```text
client 127.0.0.1 {
  secret     = mysecret
}
```

Change `/etc/freeradius/sql.conf`:

```ini
        server = "localhost"
        login = "root"
        password = "xxxx"
```

Uncomment in `/etc/freeradius/sites-available/default`:

```text
authorize {
          sql
}

accounting {
         sql
}
```

Uncomment in `/etc/freeradius/radiusd.conf`:

```text
       $INCLUDE sql.conf
```

## Configure MySQL database for FreeRadius

```bash
mysql -u root --password=xxxx
mysql> CREATE DATABASE radius;
mysql> exit

mysql -u root --password=xxxx radius < /var/www/daloradius/contrib/db/fr2-mysql-daloradius-and-freeradius.sql
```

## daloRADIUS configuration

Modify this file `/var/www/daloradius/library/daloradius.conf.php`

```php
$configValues['CONFIG_DB_PASS'] = 'xxxx';
$configValues['CONFIG_MAINT_TEST_USER_RADIUSSECRET'] = 'mysecret';
$configValues['CONFIG_DB_TBL_RADUSERGROUP'] = 'radusergroup';
```

You also need to modify following configuration files to setup sign in web pages
`/var/www/signup-*/library/daloradius.conf.php`:

```php
$configValues['CONFIG_DB_PASS'] = 'xxxx';
$configValues['CONFIG_DB_NAME'] = 'radius';
$configValues['CONFIG_DB_TBL_RADUSERGROUP'] = 'radusergroup';
$configValues['CONFIG_SIGNUP_SUCCESS_MSG_LOGIN_LINK'] = "Click <b>here</b>".
                                        " to return to the Login page and start your surfing";
```

Change lines in `/var/www/signup*/index.php` to (changed 'User-Password' ->
'Cleartext-Password' and '==' -> ':='):

```php
$sql = "INSERT INTO ".$configValues['CONFIG_DB_TBL_RADCHECK']." (id, Username, Attribute, op, Value) ".
                                        " VALUES (0, '$username', 'Cleartext-Password', ':=', '$password')";
```

Another file that needs to be modified to communicate with CoovaChilli is
`/var/www/hotspotlogin/hotspotlogin.php`

```php
$uamsecret = "uamsecret";
```

Now you should be able to reach daloRADIUS installation on
<http://127.0.0.1/daloradius/>

```text
username: administrator
password: radius
```

## Routing

We should not forget to enable packet forwarding and setup NAT:

```bash
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
echo 1 > /proc/sys/net/ipv4/ip_forward
sed --in-place=.old 's/^#\(net.ipv4.ip_forward=1\)/\1/' /etc/sysctl.conf
sysctl -p
```

## CoovaChilli configuration

Let's start with `/etc/chilli/defaults`:

```ini
HS_NETWORK=192.168.10.0
HS_UAMLISTEN=192.168.10.1

HS_RADSECRET=mysecret
HS_UAMSECRET=uamsecret
HS_UAMFORMAT=https://\$HS_UAMLISTEN/hotspotlogin/hotspotlogin.php
HS_UAMHOMEPAGE=https://\$HS_UAMLISTEN
```

Then don't forget to enable CoovaChilli to start in `/etc/default/chilli`:

```ini
START_CHILLI=1
```

Maybe you need to execute chilli and radius server with some debug options to
see "errors" during client connection:

```bash
chilli --fg --debug
freeradius -X
```

Few links we created:

- `http://192.168.10.1/signup-free/` - sign up page (if you don't have username/password)
- `http://192.168.10.1:3990/prelogin` - use for login to your portal
- `http://192.168.10.1/daloradius/` - daloradius admin page
- `http://192.168.10.1/phpmyadmin/` - phpmyadmin page (useful for sql database)

This how-to describes a simple configuration of CoovaChilli so there are many
things to configure. I didn't mention anything about security - so it's up to
you to tweak it yourself.

You can find additional info on this web page:

[https://help.ubuntu.com/community/WifiDocs/CoovaChilli](https://help.ubuntu.com/community/WifiDocs/CoovaChilli)

Enjoy... ;-)
