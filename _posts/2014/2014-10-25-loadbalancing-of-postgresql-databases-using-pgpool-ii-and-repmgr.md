---
title: Loadbalancing of PostgreSQL databases using pgpool-II and repmgr
author: Petr Ruzicka
date: 2014-10-25
description: Loadbalancing of PostgreSQL databases using pgpool-II and repmgr
categories: [Linux]
tags: [replication, database, wal, postgresql, repmgr, ha, streaming replication, pgpool, loadbalancing]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2014/10/loadbalancing-of-postgresql-databases.html)
{: .prompt-info }

I had to solve the [PostgreSQL](https://www.postgresql.org/) HA and Redundancy a
few weeks ago. A lot has been written about this topic, but I was not able to
find a guide describing pgpool-II and repmgr. After reading some documents I
built the solution which I'm going to describe.

In short it contains the Master/Slave DB [Streaming
replication](https://wiki.postgresql.org/wiki/Streaming_Replication) and
[pgpool](https://www.pgpool.net/) load distribution and HA. The replication
"part" is managed by [repmgr](https://www.repmgr.org/).

Here is the network diagram:

![image](https://rawgithub.com/ruzickap/linux.xvx.cz/gh-pages/pics/postgresql_pgpool_repmgr/diagram.svg)

- Master PostgreSQL database installation - cz01-psql01:

```bash
#PostgreSQL installation
yum localinstall -y http://yum.postgresql.org/9.3/redhat/rhel-6-x86_64/pgdg-redhat93-9.3-1.noarch.rpm
yum install -y postgresql93-server repmgr
yum install -y --enablerepo=centos-base postgresql93-contrib
service postgresql-9.3 initdb
chkconfig postgresql-9.3 on

sed -i.orig \
-e "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" \
-e "s/^#shared_preload_libraries = ''/shared_preload_libraries = 'repmgr_funcs'/" \
-e "s/^#wal_level = minimal/wal_level = hot_standby/" \
-e "s/^#archive_mode = off/archive_mode = on/" \
-e "s@^#archive_command = ''@archive_command = 'cd .'@" \
-e "s/^#max_wal_senders = 0/max_wal_senders = 1/" \
-e "s/^#wal_keep_segments = 0/wal_keep_segments = 5000/" \
-e "s/^#\(wal_sender_timeout =.*\)/\1/" \
-e "s/^#hot_standby = off/hot_standby = on/" \
-e "s/^#log_min_duration_statement = -1/log_min_duration_statement = 0/" \
-e "s/^log_line_prefix = '< %m >'/log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d '/" \
-e "s/^#log_checkpoints =.*/log_checkpoints = on/" \
-e "s/^#log_connections =.*/log_connections = on/" \
-e "s/^#log_disconnections =.*/log_disconnections = on/" \
-e "s/^#log_lock_waits = off/log_lock_waits = on/" \
-e "s/^#log_statement = 'none'/log_statement = 'all'/" \
-e "s/^#log_temp_files = -1/log_temp_files = 0/" \
/var/lib/pgsql/9.3/data/postgresql.conf

cat >> /var/lib/pgsql/9.3/data/pg_hba.conf << EOF
host    all             admin           0.0.0.0/0               md5
host    all             all             10.32.243.0/24          md5
# cz01-psql01
host    repmgr          repmgr          10.32.243.147/32        trust
host    replication     repmgr          10.32.243.147/32        trust
# cz01-psql02
host    repmgr          repmgr          10.32.243.148/32        trust
host    replication     repmgr          10.32.243.148/32        trust
EOF

for SERVER in cz01-psql01 cz01-psql02 cz01-pgpool-ha cz01-pgpool01 cz01-pgpool02; do
  echo "$SERVER.example.com:5432:postgres:admin:password123" >> ~/.pgpass
  echo "$SERVER.example.com:5432:repmgr:repmgr:repmgr_password" >> ~/.pgpass
done
chmod 0600 ~/.pgpass
cp ~/.pgpass /var/lib/pgsql/

#Configure repmgr
mkdir /var/lib/pgsql/repmgr

cat > /var/lib/pgsql/repmgr/repmgr.conf << EOF
cluster=pgsql_cluster
node=1
node_name=cz01-psql01
conninfo='host=cz01-psql01.example.com user=repmgr dbname=repmgr'
pg_bindir=/usr/pgsql-9.3/bin/
master_response_timeout=5
reconnect_attempts=2
reconnect_interval=2
failover=manual
promote_command='/usr/pgsql-9.3/bin/repmgr standby promote -f /var/lib/pgsql/repmgr/repmgr.conf'
follow_command='/usr/pgsql-9.3/bin/repmgr standby follow -f /var/lib/pgsql/repmgr/repmgr.conf'
EOF

cp -r /root/.ssh /var/lib/pgsql/
chown -R postgres:postgres /var/lib/pgsql/.ssh /var/lib/pgsql/.pgpass /var/lib/pgsql/repmgr

echo 'PATH=/usr/pgsql-9.3/bin:$PATH' >> /var/lib/pgsql/.bash_profile
service postgresql-9.3 start

#Add users
sudo -u postgres psql -c "CREATE ROLE admin SUPERUSER CREATEDB CREATEROLE INHERIT REPLICATION LOGIN ENCRYPTED PASSWORD 'password123';"
sudo -u postgres psql -c "CREATE USER repmgr SUPERUSER LOGIN ENCRYPTED PASSWORD 'repmgr_password';"
sudo -u postgres psql -c "CREATE DATABASE repmgr OWNER repmgr;"

#Register DB instance as master
su - postgres -c "repmgr -f /var/lib/pgsql/repmgr/repmgr.conf --verbose master register"

#Configure SSL Layer for PostgreSQL
sed -i.orig \
-e 's@\$dir/cacert.pem@\$dir/example.com-ca.crt @' \
-e 's@\$dir/crl.pem@\$dir/example.com-ca.crl @' \
-e 's@\$dir/private/cakey.pem@\$dir/private/example.com-ca.key @' \
-e 's/^\(crlnumber\)/#\1/' \
-e 's/= XX/= CZ/' \
-e 's/^#\(stateOrProvinceName_default.*\) Default Province/\1 Czech Republic/' \
-e 's/= Default City/= Brno/' \
-e 's/= Default Company Ltd/= Example, Inc\./' \
-e 's/= policy_match/= policy_anything/' \
-e 's/^#\(unique_subject\)/\1/' /etc/pki/tls/openssl.cnf

touch /etc/pki/CA/index.txt
echo 01 > /etc/pki/CA/serial
cd /etc/pki/CA

# Private key for CA
(
umask 077
openssl genrsa -passout pass:password123 -out private/example.com-ca.key 1024
openssl pkey -text -passout pass:password123 -in private/example.com-ca.key > private/example.com-ca.key.info
)

SUBJ="
C=CZ
ST=Czech Republic
O=Example, Inc.
localityName=Brno
commonName=example.com Certificate Authority
"

openssl req -passin pass:password123 -subj "$(echo -n "$SUBJ" | tr "\n" "/")" -new -x509 -key private/example.com-ca.key -days 3650 -out example.com-ca.crt
openssl x509 -noout -text -in example.com-ca.crt > example.com-ca.crt.info

# cz01-psql01 Certificate
openssl genrsa -passout pass:password123 -des3 -out cz01-psql01.example.com_priv_encrypted.key 2048
openssl rsa -passin pass:password123 -in cz01-psql01.example.com_priv_encrypted.key -out cz01-psql01.example.com_priv.key

SUBJ="
C=CZ
ST=Czech Republic
O=Example
OU=Deployment
L=Brno
CN=cz01-psql01.example.com
emailAddress=root@example.com
"
openssl req -passin pass:password123 -new -subj "$(echo -n "$SUBJ" | tr "\n" "/")" -days 3650 -key cz01-psql01.example.com_priv_encrypted.key -out cz01-psql01.example.com.csr

openssl ca -passin pass:password123 -batch -in cz01-psql01.example.com.csr -out cz01-psql01.example.com.crt
openssl x509 -noout -text -in cz01-psql01.example.com.crt > cz01-psql01.example.com.crt.info

cp /etc/pki/CA/cz01-psql01.example.com.crt /var/lib/pgsql/9.3/server.crt
cp /etc/pki/CA/cz01-psql01.example.com_priv.key /var/lib/pgsql/9.3/server.key
chown postgres:postgres /var/lib/pgsql/9.3/server.*
chmod 0600 /var/lib/pgsql/9.3/server.key

sed -i \
-e "s/#ssl = off/ssl = on/" \
-e "s@#ssl_cert_file = 'server.crt'@ssl_cert_file = '../server.crt'@" \
-e "s@#ssl_key_file = 'server.key'@ssl_key_file = '../server.key'@" \
/var/lib/pgsql/9.3/data/postgresql.conf

service postgresql-9.3 restart

# Quick Test
export PGSSLMODE=require
psql --host cz01-psql01.example.com --username=fuzeme --dbname=fuzers -w -l
```

- Slave PostgreSQL database installation - cz01-psql02:

```bash
#PostgreSQL installation
yum localinstall -y http://yum.postgresql.org/9.3/redhat/rhel-6-x86_64/pgdg-redhat93-9.3-1.noarch.rpm
yum install -y postgresql93-server repmgr
yum install -y --enablerepo=centos-base postgresql93-contrib
chkconfig postgresql-9.3 on

echo 'PATH=/usr/pgsql-9.3/bin:$PATH' >> /var/lib/pgsql/.bash_profile

scp -r cz01-psql01.example.com:/root/{.pgpass,.ssh} /root/
cp -r /root/{.pgpass,.ssh} /var/lib/pgsql/
chown -R postgres:postgres /var/lib/pgsql/.pgpass /var/lib/pgsql/.ssh

#Check the connection to primary node
su - postgres -c "psql --username=repmgr --dbname=repmgr --host cz01-psql01.example.com -w -l"

#Replicate the DB from the master mode
su - postgres -c "repmgr -D /var/lib/pgsql/9.3/data -d repmgr -p 5432 -U repmgr -R postgres --verbose standby clone cz01-psql01.example.com"

#Configure the repmgr
mkdir /var/lib/pgsql/repmgr
cat > /var/lib/pgsql/repmgr/repmgr.conf << EOF
cluster=pgsql_cluster
node=2
node_name=cz01-psql02
conninfo='host=cz01-psql02.example.com user=repmgr dbname=repmgr'
pg_bindir=/usr/pgsql-9.3/bin/
master_response_timeout=5
reconnect_attempts=2
reconnect_interval=2
failover=manual
promote_command='/usr/pgsql-9.3/bin/repmgr standby promote -f /var/lib/pgsql/repmgr/repmgr.conf'
follow_command='/usr/pgsql-9.3/bin/repmgr standby follow -f /var/lib/pgsql/repmgr/repmgr.conf'
EOF

chown -R postgres:postgres /var/lib/pgsql/repmgr

# cz01-psql02 Certificate
cd /etc/pki/CA
openssl genrsa -passout pass:password123 -des3 -out cz01-psql02.example.com_priv_encrypted.key 2048
openssl rsa -passin pass:password123 -in cz01-psql02.example.com_priv_encrypted.key -out cz01-psql02.example.com_priv.key

SUBJ="
C=CZ
ST=Czech Republic
O=Example
OU=Deployment
L=Brno
CN=cz01-psql02.example.com
emailAddress=root@example.com
"

openssl req -passin pass:password123 -new -subj "$(echo -n "$SUBJ" | tr "\n" "/")" -days 3650 -key cz01-psql02.example.com_priv_encrypted.key -out cz01-psql02.example.com.csr

scp /etc/pki/CA/cz01-psql02.example.com.csr root@cz01-psql01.example.com:/etc/pki/CA/

ssh root@cz01-psql01.example.com << EOF
cd /etc/pki/CA
openssl ca -passin pass:password123 -batch -in cz01-psql02.example.com.csr -out cz01-psql02.example.com.crt
openssl x509 -noout -text -in cz01-psql02.example.com.crt > cz01-psql02.example.com.crt.info
EOF

scp root@cz01-psql01.example.com:/etc/pki/CA/cz01-psql02.example.com.crt /etc/pki/CA/

cp /etc/pki/CA/cz01-psql02.example.com.crt /var/lib/pgsql/9.3/server.crt
cp /etc/pki/CA/cz01-psql02.example.com_priv.key /var/lib/pgsql/9.3/server.key
chown postgres:postgres /var/lib/pgsql/9.3/server.*

chmod 0600 /var/lib/pgsql/9.3/server.key

service postgresql-9.3 start

#Register the DB instance as slave
su - postgres -c "repmgr -f /var/lib/pgsql/repmgr/repmgr.conf --verbose standby register"
```

- pgpool server installation (common for primary/secondary node) -
cz01-pgpool0{1,2}:

```bash
#pgpool installation
yum localinstall -y http://yum.postgresql.org/9.3/redhat/rhel-6-x86_64/pgdg-redhat93-9.3-1.noarch.rpm
yum install -y pgpool-II-93 postgresql93

scp -r cz01-psql01.example.com:/root/{.ssh,.pgpass} /root/
scp cz01-psql01.example.com:/root/.pgpass /root/

cp /etc/pgpool-II-93/pcp.conf.sample /etc/pgpool-II-93/pcp.conf
echo "admin:`pg_md5 password123`" >> /etc/pgpool-II-93/pcp.conf

sed \
-e "s/^listen_addresses = .localhost./listen_addresses = '*'/" \
-e "s/^log_destination = .stderr./log_destination = 'syslog'/" \
-e "s/^port = .*/port = 5432/" \
-e "s/^backend_hostname0 =.*/backend_hostname0 = 'cz01-psql01.example.com'/" \
-e "s/^#backend_flag0/backend_flag0/" \
-e "s/^#backend_hostname1 =.*/backend_hostname1 = 'cz01-psql02.example.com'/" \
-e "s/^#backend_port1 = 5433/backend_port1 = 5432/" \
-e "s/^#backend_weight1/backend_weight1/" \
-e "s/^#backend_data_directory1 =.*/backend_data_directory1 = '\/var\/lib\/pgsql\/9.3\/data'/" \
-e "s/^#backend_flag1/backend_flag1/" \
-e "s/^log_hostname =.*/log_hostname = on/" \
-e "s/^syslog_facility =.*/syslog_facility = 'daemon.info'/" \
-e "s/^sr_check_user =.*/sr_check_user = 'admin'/" \
-e "s/^sr_check_password =.*/sr_check_password = 'password123'/" \
-e "s/^health_check_period =.*/health_check_period = 10/" \
-e "s/^health_check_user =.*/health_check_user = 'admin'/" \
-e "s/^health_check_password =.*/health_check_password = 'password123'/" \
-e "s/^use_watchdog =.*/use_watchdog = on/" \
-e "s/^delegate_IP =.*/delegate_IP = '10.32.243.250'/" \
-e "s/^netmask 255.255.255.0/netmask 255.255.255.128/" \
-e "s/^heartbeat_device0 =.*/heartbeat_device0 = 'eth0'/" \
-e "s/^#other_pgpool_port0 =.*/other_pgpool_port0 = 5432/" \
-e "s/^#other_wd_port0 = 9000/other_wd_port0 = 9000/" \
-e "s/^load_balance_mode = off/load_balance_mode = on/" \
-e "s/^master_slave_mode = off/master_slave_mode = on/" \
-e "s/^master_slave_sub_mode =.*/master_slave_sub_mode = 'stream'/" \
-e "s@^failover_command = ''@failover_command = '/etc/pgpool-II-93/failover_stream.sh %d %H'@" \
-e "s/^recovery_user = 'nobody'/recovery_user = 'admin'/" \
-e "s/^recovery_password = ''/recovery_password = 'password123'/" \
-e "s/^recovery_1st_stage_command = ''/recovery_1st_stage_command = 'basebackup.sh'/" \
-e "s/^sr_check_period = 0/sr_check_period = 10/" \
-e "s/^delay_threshold = 0/delay_threshold = 10000000/" \
-e "s/^log_connections = off/log_connections = on/" \
-e "s/^log_statement = off/log_statement = on/" \
-e "s/^log_per_node_statement = off/log_per_node_statement = on/" \
-e "s/^log_standby_delay = 'none'/log_standby_delay = 'always'/" \
-e "s/^enable_pool_hba = off/enable_pool_hba = on/" \
/etc/pgpool-II-93/pgpool.conf.sample > /etc/pgpool-II-93/pgpool.conf

cat > /etc/pgpool-II-93/failover_stream.sh << \EOF
#!/bin/sh
# Failover command for streaming replication.
#
# Arguments: $1: failed node id. $2: new master hostname.

failed_node=$1
new_master=$2

(
date
echo "Failed node: $failed_node"
set -x

# Promote standby/slave to be a new master (old master failed)
/usr/bin/ssh -T -l postgres $new_master "/usr/pgsql-9.3/bin/repmgr -f /var/lib/pgsql/repmgr/repmgr.conf standby promote 2>/dev/null 1>/dev/null <&-"

exit 0;
) 2>&1 | tee -a /tmp/failover_stream.sh.log
EOF
chmod 755 /etc/pgpool-II-93/failover_stream.sh

cp /etc/pgpool-II-93/pool_hba.conf.sample /etc/pgpool-II-93/pool_hba.conf
echo "host    all         all         0.0.0.0/0             md5" >> /etc/pgpool-II-93/pool_hba.conf

mkdir -p /var/lib/pgsql/9.3/data
groupadd -g 26 -o -r postgres
useradd -M -n -g postgres -o -r -d /var/lib/pgsql -s /bin/bash -c "PostgreSQL Server" -u 26 postgres

cp -R /root/.ssh /var/lib/pgsql/
sed -i '/^User /d' /var/lib/pgsql/.ssh/config

pg_md5 -m -u admin password123

chown -R postgres:postgres /var/lib/pgsql /etc/pgpool-II-93/pool_passwd

chmod 6755 /sbin/ifconfig
chmod 6755 /sbin/arping

chkconfig pgpool-II-93 on
```

- Primary pgpool server installation - cz01-pgpool01:

```bash
sed \
-e "s/^wd_hostname =.*/wd_hostname = 'cz01-pgpool01.example.com'/" \
-e "s/^heartbeat_destination0 =.*/heartbeat_destination0 = 'cz01-pgpool02.example.com'/" \
-e "s/^#other_pgpool_hostname0 =.*/other_pgpool_hostname0 = 'cz01-pgpool02.example.com'/" \
-i /etc/pgpool-II-93/pgpool.conf

service pgpool-II-93 start
```

- Secondary pgpool server installation - cz01-pgpool02:

```bash
sed \
-e "s/^wd_hostname =.*/wd_hostname = 'cz01-pgpool02.example.com'/" \
-e "s/^heartbeat_destination0 =.*/heartbeat_destination0 = 'cz01-pgpool01.example.com'/" \
-e "s/^#other_pgpool_hostname0 =.*/other_pgpool_hostname0 = 'cz01-pgpool01.example.com'/" \
-i /etc/pgpool-II-93/pgpool.conf

service pgpool-II-93 start
```

Now the all 4 server should be configured according the picture mentioned above.
To be sure everything is working properly I decided to do various tests by
stopping/starting the databases to see how all components are ready for outages.
In the next pare there will be a lot of outputs of logs+commands which can be
handy for troubleshooting in the future and which will test the proper
configuration.

All the files modified and used for the configuration above can be found in the
[postgresql_pgpool_repmgr
repository](https://github.com/ruzickap/linux.xvx.cz/tree/gh-pages/files/postgresql_pgpool_repmgr).

## Testing

### Check the cluster status

```bash
cz01-pgpool02 ~ # ssh postgres@cz01-psql02.example.com "/usr/pgsql-9.3/bin/repmgr --verbose -f /var/lib/pgsql/repmgr/repmgr.conf cluster show"
Warning: Permanently added 'cz01-psql02.example.com,10.32.243.148' (RSA) to the list of known hosts.

[2014-10-23 14:39:40] [INFO] repmgr connecting to database
Opening configuration file: /var/lib/pgsql/repmgr/repmgr.conf
Role | Connection String
* master | host=cz01-psql01.example.com user=repmgr dbname=repmgr
 standby | host=cz01-psql02.example.com user=repmgr dbname=repmgr
cz01-pgpool02 ~ # pcp_node_count 1 localhost 9898 admin password123
2
cz01-pgpool02 ~ # pcp_node_info 1 localhost 9898 admin password123 0
cz01-psql01.example.com 5432 1 0.500000
cz01-pgpool02 ~ # pcp_node_info 1 localhost 9898 admin password123 1
cz01-psql02.example.com 5432 1 0.500000
```

### Check if the replication is working

```bash
cz01-pgpool02 ~ # psql --username=admin --dbname=postgres --host cz01-pgpool-ha.example.com -w -c "create database mydb"
CREATE DATABASE
cz01-pgpool02 ~ # psql --username=admin --dbname=postgres --host cz01-pgpool-ha.example.com -w -l | grep mydb
 mydb | admin | UTF8 | en_US.UTF-8 | en_US.UTF-8 |
cz01-pgpool02 ~ # psql --username=admin --dbname=postgres --host cz01-psql01.example.com -w -l | grep mydb
 mydb | admin | UTF8 | en_US.UTF-8 | en_US.UTF-8 |
cz01-pgpool02 ~ # psql --username=admin --dbname=postgres --host cz01-psql02.example.com -w -l | grep mydb
 mydb | admin | UTF8 | en_US.UTF-8 | en_US.UTF-8 |
```

### Check what is the primapry pgpool (it has 2 IPs)

```bash
cz01-pgpool02 ~ # ssh -q cz01-pgpool01 "ip a s"
1: lo: mtu 16436 qdisc noqueue state UNKNOWN
 link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
 inet 127.0.0.1/8 scope host lo
2: eth0: mtu 1500 qdisc pfifo_fast state UP qlen 1000
 link/ether 00:50:56:91:0a:86 brd ff:ff:ff:ff:ff:ff
 inet 10.32.243.157/25 brd 10.32.243.255 scope global eth0
 inet 10.32.243.250/24 brd 10.32.243.255 scope global eth0:0
```

### Stop the Master DB

```bash
cz01-pgpool02 ~ # date && ssh root@cz01-psql01.example.com "service postgresql-9.3 stop"
Thu Oct 23 14:43:09 CEST 2014
Warning: Permanently added 'cz01-psql01.example.com,10.32.243.147' (RSA) to the list of known hosts.

Stopping postgresql-9.3 service: [ OK ]
```

- The pgpool is monitoring both master and slave databases if they are
responding. If one of them is not responding the pgpool executes the
"failover_stream.sh" file. This script is responsible for promoting the slave to
be a new master. The result is that the read-only slave will become read/write
master. In the diagram below I used the red colour to see the changes which were
done when slave was promoted to master.

![image](https://rawgithub.com/ruzickap/linux.xvx.cz/gh-pages/pics/postgresql_pgpool_repmgr/diagram_master_down.svg)

### pgpool01 logs right after the master was stopped

```bash
cz01-pgpool01 ~ # cat /var/log/local0
...
2014-10-23T14:43:11.547651+02:00 cz01-pgpool01 pgpool[23301]: connect_inet_domain_socket: getsockopt() detected error: Connection refused
2014-10-23T14:43:11.547678+02:00 cz01-pgpool01 pgpool[23301]: make_persistent_db_connection: connection to cz01-psql01.example.com(5432) failed
2014-10-23T14:43:11.562642+02:00 cz01-pgpool01 pgpool[23301]: check_replication_time_lag: could not connect to DB node 0, check sr_check_user and sr_check_password
2014-10-23T14:43:12.327080+02:00 cz01-pgpool01 pgpool[23257]: connect_inet_domain_socket: getsockopt() detected error: Connection refused
2014-10-23T14:43:12.327127+02:00 cz01-pgpool01 pgpool[23257]: make_persistent_db_connection: connection to cz01-psql01.example.com(5432) failed
2014-10-23T14:43:12.332564+02:00 cz01-pgpool01 pgpool[23257]: connect_inet_domain_socket: getsockopt() detected error: Connection refused
2014-10-23T14:43:12.332661+02:00 cz01-pgpool01 pgpool[23257]: make_persistent_db_connection: connection to cz01-psql01.example.com(5432) failed
2014-10-23T14:43:12.332740+02:00 cz01-pgpool01 pgpool[23257]: health check failed. 0 th host cz01-psql01.example.com at port 5432 is down
2014-10-23T14:43:12.332822+02:00 cz01-pgpool01 pgpool[23257]: set 0 th backend down status
2014-10-23T14:43:12.332920+02:00 cz01-pgpool01 pgpool[23257]: wd_start_interlock: start interlocking
2014-10-23T14:43:12.348543+02:00 cz01-pgpool01 pgpool[23257]: wd_assume_lock_holder: become a new lock holder
2014-10-23T14:43:12.372682+02:00 cz01-pgpool01 pgpool[23264]: wd_send_response: WD_STAND_FOR_LOCK_HOLDER received but lock holder exists already
2014-10-23T14:43:13.369470+02:00 cz01-pgpool01 pgpool[23257]: starting degeneration. shutdown host cz01-psql01.example.com(5432)
2014-10-23T14:43:13.369521+02:00 cz01-pgpool01 pgpool[23257]: Restart all children
2014-10-23T14:43:13.369544+02:00 cz01-pgpool01 pgpool[23257]: execute command: /etc/pgpool-II-93/failover_stream.sh 0 cz01-psql02.example.com
2014-10-23T14:43:15.916452+02:00 cz01-pgpool01 pgpool[23257]: find_primary_node_repeatedly: waiting for finding a primary node
2014-10-23T14:43:15.933033+02:00 cz01-pgpool01 pgpool[23257]: find_primary_node: primary node id is 1
2014-10-23T14:43:15.937969+02:00 cz01-pgpool01 pgpool[23257]: wd_end_interlock: end interlocking
2014-10-23T14:43:16.963481+02:00 cz01-pgpool01 pgpool[23257]: failover: set new primary node: 1
2014-10-23T14:43:16.963534+02:00 cz01-pgpool01 pgpool[23257]: failover: set new master node: 1
2014-10-23T14:43:17.051441+02:00 cz01-pgpool01 pgpool[23301]: worker process received restart request
2014-10-23T14:43:17.055720+02:00 cz01-pgpool01 pgpool[23257]: failover done. shutdown host cz01-psql01.example.com(5432)
2014-10-23T14:43:18.059487+02:00 cz01-pgpool01 pgpool[23300]: pcp child process received restart request
2014-10-23T14:43:18.064463+02:00 cz01-pgpool01 pgpool[23257]: PCP child 23300 exits with status 256 in failover()
2014-10-23T14:43:18.064493+02:00 cz01-pgpool01 pgpool[23257]: fork a new PCP child pid 26164 in failover()
2014-10-23T14:43:18.064499+02:00 cz01-pgpool01 pgpool[23257]: worker child 23301 exits with status 256
2014-10-23T14:43:18.065907+02:00 cz01-pgpool01 pgpool[23257]: fork a new worker child pid 26165
```

### psql01 (masted db) logs right after the master was stopped

```bash
cz01-psql01 / # cat /var/lib/pgsql/9.3/data/pg_log/postgresql-Thu.log
...
2014-10-23 14:43:10 CEST [18254]: [6-1] user=,db= LOG: received fast shutdown request
2014-10-23 14:43:10 CEST [18254]: [7-1] user=,db= LOG: aborting any active transactions
2014-10-23 14:43:10 CEST [24392]: [13-1] user=admin,db=postgres FATAL: terminating connection due to administrator command
2014-10-23 14:43:10 CEST [24392]: [14-1] user=admin,db=postgres LOG: disconnection: session time: 0:03:01.366 user=admin database=postgres host=10.32.243.157 port=53814
2014-10-23 14:43:10 CEST [24386]: [13-1] user=admin,db=postgres FATAL: terminating connection due to administrator command
2014-10-23 14:43:10 CEST [24386]: [14-1] user=admin,db=postgres LOG: disconnection: session time: 0:03:08.732 user=admin database=postgres host=10.32.243.157 port=53812
2014-10-23 14:43:10 CEST [18266]: [2-1] user=,db= LOG: autovacuum launcher shutting down
2014-10-23 14:43:10 CEST [18263]: [27-1] user=,db= LOG: shutting down
2014-10-23 14:43:10 CEST [18263]: [28-1] user=,db= LOG: checkpoint starting: shutdown immediate
2014-10-23 14:43:10 CEST [18263]: [29-1] user=,db= LOG: checkpoint complete: wrote 1 buffers (0.0%); 0 transaction log file(s) added, 0 removed, 0 recycled; write=0.002 s, sync=0.002 s, total=0.479 s; sync files=1, longest=0.002 s, average=0.002 s
2014-10-23 14:43:10 CEST [18263]: [30-1] user=,db= LOG: database system is shut down
2014-10-23 14:43:11 CEST [18438]: [3-1] user=repmgr,db=[unknown] LOG: disconnection: session time: 0:48:37.268 user=repmgr database= host=10.32.243.148 port=50909
```

### psql02 (slave db) logs right after the master was stopped

```bash
cz01-psql02 / # cat /var/lib/pgsql/9.3/data/pg_log/postgresql-Thu.log
...
2014-10-23 14:43:11 CEST [18031]: [2-1] user=,db= LOG: replication terminated by primary server
2014-10-23 14:43:11 CEST [18031]: [3-1] user=,db= DETAIL: End of WAL reached on timeline 1 at 0/61000090.
2014-10-23 14:43:11 CEST [18031]: [4-1] user=,db= FATAL: could not send end-of-streaming message to primary: no COPY in progress
2014-10-23 14:43:11 CEST [18030]: [5-1] user=,db= LOG: record with zero length at 0/61000090
2014-10-23 14:43:11 CEST [24120]: [1-1] user=[unknown],db=[unknown] LOG: connection received: host=10.32.243.157 port=52991
2014-10-23 14:43:11 CEST [24120]: [2-1] user=admin,db=postgres LOG: connection authorized: user=admin database=postgres
2014-10-23 14:43:11 CEST [24120]: [3-1] user=admin,db=postgres LOG: disconnection: session time: 0:00:00.010 user=admin database=postgres host=10.32.243.157 port=52991
2014-10-23 14:43:13 CEST [24121]: [1-1] user=[unknown],db=[unknown] LOG: connection received: host=10.32.243.158 port=53841
2014-10-23 14:43:13 CEST [24121]: [2-1] user=admin,db=postgres LOG: connection authorized: user=admin database=postgres
2014-10-23 14:43:13 CEST [24121]: [3-1] user=admin,db=postgres LOG: disconnection: session time: 0:00:00.009 user=admin database=postgres host=10.32.243.158 port=53841
2014-10-23 14:43:13 CEST [23435]: [9-1] user=admin,db=postgres LOG: disconnection: session time: 0:03:11.742 user=admin database=postgres host=10.32.243.157 port=52915
2014-10-23 14:43:13 CEST [23438]: [5-1] user=admin,db=postgres LOG: disconnection: session time: 0:03:04.381 user=admin database=postgres host=10.32.243.157 port=52917
2014-10-23 14:43:13 CEST [24129]: [1-1] user=[unknown],db=[unknown] LOG: connection received: host=10.32.243.148 port=54332
2014-10-23 14:43:13 CEST [24129]: [2-1] user=repmgr,db=repmgr LOG: connection authorized: user=repmgr database=repmgr
2014-10-23 14:43:13 CEST [24129]: [3-1] user=repmgr,db=repmgr LOG: statement: WITH pg_version(ver) AS (SELECT split_part(version(), ' ', 2)) SELECT split_part(ver, '.', 1), split_part(ver, '.', 2) FROM pg_version
2014-10-23 14:43:13 CEST [24129]: [4-1] user=repmgr,db=repmgr LOG: duration: 2.850 ms
2014-10-23 14:43:13 CEST [24129]: [5-1] user=repmgr,db=repmgr LOG: statement: SELECT pg_is_in_recovery()
2014-10-23 14:43:13 CEST [24129]: [6-1] user=repmgr,db=repmgr LOG: duration: 0.339 ms
2014-10-23 14:43:13 CEST [24129]: [7-1] user=repmgr,db=repmgr LOG: statement: SELECT id, conninfo FROM "repmgr_pgsql_cluster".repl_nodes WHERE cluster = 'pgsql_cluster' and not witness
2014-10-23 14:43:13 CEST [24129]: [8-1] user=repmgr,db=repmgr LOG: duration: 2.634 ms
2014-10-23 14:43:13 CEST [24130]: [1-1] user=[unknown],db=[unknown] LOG: connection received: host=10.32.243.148 port=54334
2014-10-23 14:43:13 CEST [24130]: [2-1] user=repmgr,db=repmgr LOG: connection authorized: user=repmgr database=repmgr
2014-10-23 14:43:13 CEST [24130]: [3-1] user=repmgr,db=repmgr LOG: statement: SELECT pg_is_in_recovery()
2014-10-23 14:43:13 CEST [24130]: [4-1] user=repmgr,db=repmgr LOG: duration: 1.347 ms
2014-10-23 14:43:13 CEST [24129]: [9-1] user=repmgr,db=repmgr LOG: statement: SELECT setting FROM pg_settings WHERE name = 'data_directory'
2014-10-23 14:43:13 CEST [24130]: [5-1] user=repmgr,db=repmgr LOG: disconnection: session time: 0:00:00.024 user=repmgr database=repmgr host=10.32.243.148 port=54334
2014-10-23 14:43:13 CEST [24129]: [10-1] user=repmgr,db=repmgr LOG: duration: 4.954 ms
2014-10-23 14:43:13 CEST [24129]: [11-1] user=repmgr,db=repmgr LOG: disconnection: session time: 0:00:00.067 user=repmgr database=repmgr host=10.32.243.148 port=54332
2014-10-23 14:43:13 CEST [18021]: [6-1] user=,db= LOG: received fast shutdown request
2014-10-23 14:43:13 CEST [18021]: [7-1] user=,db= LOG: aborting any active transactions
2014-10-23 14:43:13 CEST [18032]: [28-1] user=,db= LOG: shutting down
2014-10-23 14:43:13 CEST [18032]: [29-1] user=,db= LOG: restartpoint starting: shutdown immediate
2014-10-23 14:43:13 CEST [18032]: [30-1] user=,db= LOG: restartpoint complete: wrote 6 buffers (0.0%); 0 transaction log file(s) added, 0 removed, 0 recycled; write=0.002 s, sync=0.002 s, total=0.008 s; sync files=6, longest=0.000 s, average=0.000 s
2014-10-23 14:43:13 CEST [18032]: [31-1] user=,db= LOG: recovery restart point at 0/61000028
2014-10-23 14:43:13 CEST [18032]: [32-1] user=,db= DETAIL: last completed transaction was at log time 2014-10-23 14:40:08.829957+02
2014-10-23 14:43:13 CEST [18032]: [33-1] user=,db= LOG: database system is shut down
2014-10-23 14:43:14 CEST [24141]: [1-1] user=,db= LOG: database system was shut down in recovery at 2014-10-23 14:43:13 CEST
2014-10-23 14:43:14 CEST [24141]: [2-1] user=,db= LOG: database system was not properly shut down; automatic recovery in progress
2014-10-23 14:43:14 CEST [24141]: [3-1] user=,db= LOG: consistent recovery state reached at 0/61000090
2014-10-23 14:43:14 CEST [24141]: [4-1] user=,db= LOG: record with zero length at 0/61000090
2014-10-23 14:43:14 CEST [24141]: [5-1] user=,db= LOG: redo is not required
2014-10-23 14:43:14 CEST [24141]: [6-1] user=,db= LOG: checkpoint starting: end-of-recovery immediate
2014-10-23 14:43:14 CEST [24141]: [7-1] user=,db= LOG: checkpoint complete: wrote 0 buffers (0.0%); 0 transaction log file(s) added, 0 removed, 0 recycled; write=0.002 s, sync=0.000 s, total=0.005 s; sync files=0, longest=0.000 s, average=0.000 s
2014-10-23 14:43:14 CEST [24145]: [1-1] user=,db= LOG: autovacuum launcher started
2014-10-23 14:43:14 CEST [24133]: [5-1] user=,db= LOG: database system is ready to accept connections
2014-10-23 14:43:15 CEST [24148]: [1-1] user=[unknown],db=[unknown] LOG: connection received: host=[local]
2014-10-23 14:43:15 CEST [24148]: [2-1] user=postgres,db=postgres LOG: connection authorized: user=postgres database=postgres
2014-10-23 14:43:15 CEST [24148]: [3-1] user=postgres,db=postgres LOG: disconnection: session time: 0:00:00.019 user=postgres database=postgres host=[local]
2014-10-23 14:43:15 CEST [24149]: [1-1] user=[unknown],db=[unknown] LOG: connection received: host=10.32.243.148 port=54335
2014-10-23 14:43:15 CEST [24149]: [2-1] user=repmgr,db=repmgr LOG: connection authorized: user=repmgr database=repmgr
2014-10-23 14:43:15 CEST [24149]: [3-1] user=repmgr,db=repmgr LOG: statement: SELECT pg_is_in_recovery()
2014-10-23 14:43:15 CEST [24149]: [4-1] user=repmgr,db=repmgr LOG: duration: 2.252 ms
2014-10-23 14:43:15 CEST [24149]: [5-1] user=repmgr,db=repmgr LOG: disconnection: session time: 0:00:00.030 user=repmgr database=repmgr host=10.32.243.148 port=54335
```

### failover_stream.sh output log from primary pgpool

```bash
cz01-pgpool01 / # cat /tmp/failover_stream.sh.log
Thu Oct 23 14:43:13 CEST 2014
Failed node: 0
+ /usr/bin/ssh -T -l postgres cz01-psql02.example.com '/usr/pgsql-9.3/bin/repmgr -f /var/lib/pgsql/repmgr/repmgr.conf standby promote 2>/dev/null 1>/dev/null
```

![Diagram: Failed master become slave](https://rawgithub.com/ruzickap/linux.xvx.cz/gh-pages/pics/postgresql_pgpool_repmgr/diagram_failed_master_become_slave.svg)

### Logs right after the new slave (cz01-psql01) was configured+started

```bash
cz01-psql01 / # cat /var/lib/pgsql/9.3/data/pg_log/postgresql-Thu.log
...
2014-10-23 14:52:14 CEST [26707]: [1-1] user=,db= LOG: database system was interrupted; last known up at 2014-10-23 14:52:09 CEST
2014-10-23 14:52:14 CEST [26707]: [2-1] user=,db= LOG: entering standby mode
2014-10-23 14:52:14 CEST [26708]: [1-1] user=,db= LOG: started streaming WAL from primary at 0/62000000 on timeline 1
2014-10-23 14:52:14 CEST [26707]: [3-1] user=,db= LOG: redo starts at 0/62000028
2014-10-23 14:52:14 CEST [26707]: [4-1] user=,db= LOG: consistent recovery state reached at 0/620000F0
2014-10-23 14:52:14 CEST [26698]: [5-1] user=,db= LOG: database system is ready to accept read only connections
```

### Logs from cz01-psql02 after the new slave was configured

```bash
cz01-psql02 / # cat /var/lib/pgsql/9.3/data/pg_log/postgresql-Thu.log
...
2014-10-23 14:52:08 CEST [25481]: [1-1] user=[unknown],db=[unknown] LOG: connection received: host=10.32.243.147 port=52477
2014-10-23 14:52:08 CEST [25481]: [2-1] user=repmgr,db=repmgr LOG: connection authorized: user=repmgr database=repmgr
2014-10-23 14:52:08 CEST [25481]: [3-1] user=repmgr,db=repmgr LOG: statement: WITH pg_version(ver) AS (SELECT split_part(version(), ' ', 2)) SELECT split_part(ver, '.', 1), split_part(ver, '.', 2) FROM pg_version
2014-10-23 14:52:08 CEST [25481]: [4-1] user=repmgr,db=repmgr LOG: duration: 2.790 ms
2014-10-23 14:52:08 CEST [25481]: [5-1] user=repmgr,db=repmgr LOG: statement: SELECT pg_is_in_recovery()
2014-10-23 14:52:08 CEST [25481]: [6-1] user=repmgr,db=repmgr LOG: duration: 0.451 ms
2014-10-23 14:52:08 CEST [25481]: [7-1] user=repmgr,db=repmgr LOG: statement: SELECT true FROM pg_settings WHERE name = 'wal_level' AND setting = 'hot_standby'
2014-10-23 14:52:09 CEST [25481]: [8-1] user=repmgr,db=repmgr LOG: duration: 7.175 ms
2014-10-23 14:52:09 CEST [25481]: [9-1] user=repmgr,db=repmgr LOG: statement: SELECT true FROM pg_settings WHERE name = 'wal_keep_segments' AND setting::integer >= '5000'::integer
2014-10-23 14:52:09 CEST [25481]: [10-1] user=repmgr,db=repmgr LOG: duration: 3.971 ms
2014-10-23 14:52:09 CEST [25481]: [11-1] user=repmgr,db=repmgr LOG: statement: SELECT true FROM pg_settings WHERE name = 'archive_mode' AND setting = 'on'
2014-10-23 14:52:09 CEST [25481]: [12-1] user=repmgr,db=repmgr LOG: duration: 3.191 ms
2014-10-23 14:52:09 CEST [25481]: [13-1] user=repmgr,db=repmgr LOG: statement: SELECT true FROM pg_settings WHERE name = 'hot_standby' AND setting = 'on'
2014-10-23 14:52:09 CEST [25481]: [14-1] user=repmgr,db=repmgr LOG: duration: 3.147 ms
2014-10-23 14:52:09 CEST [25481]: [15-1] user=repmgr,db=repmgr LOG: statement: SELECT pg_tablespace_location(oid) spclocation FROM pg_tablespace WHERE spcname NOT IN ('pg_default', 'pg_global')
2014-10-23 14:52:09 CEST [25481]: [16-1] user=repmgr,db=repmgr LOG: duration: 2.541 ms
2014-10-23 14:52:09 CEST [25481]: [17-1] user=repmgr,db=repmgr LOG: statement: SELECT name, setting FROM pg_settings WHERE name IN ('data_directory', 'config_file', 'hba_file', 'ident_file', 'stats_temp_directory')
2014-10-23 14:52:09 CEST [25481]: [18-1] user=repmgr,db=repmgr LOG: duration: 3.842 ms
2014-10-23 14:52:09 CEST [25481]: [19-1] user=repmgr,db=repmgr LOG: statement: SELECT pg_size_pretty(SUM(pg_database_size(oid))::bigint) FROM pg_database
2014-10-23 14:52:09 CEST [25481]: [20-1] user=repmgr,db=repmgr LOG: duration: 16.913 ms
2014-10-23 14:52:09 CEST [25481]: [21-1] user=repmgr,db=repmgr LOG: statement: SET synchronous_commit TO OFF
2014-10-23 14:52:09 CEST [25481]: [22-1] user=repmgr,db=repmgr LOG: duration: 0.282 ms
2014-10-23 14:52:09 CEST [25481]: [23-1] user=repmgr,db=repmgr LOG: statement: SELECT pg_xlogfile_name(pg_start_backup('repmgr_standby_clone_1414068729'))
2014-10-23 14:52:09 CEST [24142]: [3-1] user=,db= LOG: checkpoint starting: force wait
2014-10-23 14:52:09 CEST [25489]: [1-1] user=[unknown],db=[unknown] LOG: connection received: host=10.32.243.158 port=53963
2014-10-23 14:52:09 CEST [25489]: [2-1] user=admin,db=postgres LOG: connection authorized: user=admin database=postgres
2014-10-23 14:52:09 CEST [25489]: [3-1] user=admin,db=postgres LOG: disconnection: session time: 0:00:00.008 user=admin database=postgres host=10.32.243.158 port=53963
2014-10-23 14:52:09 CEST [25490]: [1-1] user=[unknown],db=[unknown] LOG: connection received: host=10.32.243.157 port=53120
2014-10-23 14:52:09 CEST [25490]: [2-1] user=admin,db=template1 LOG: connection authorized: user=admin database=template1
2014-10-23 14:52:09 CEST [25490]: [3-1] user=admin,db=template1 LOG: disconnection: session time: 0:00:00.008 user=admin database=template1 host=10.32.243.157 port=53120
2014-10-23 14:52:09 CEST [24142]: [4-1] user=,db= LOG: checkpoint complete: wrote 1 buffers (0.0%); 0 transaction log file(s) added, 0 removed, 0 recycled; write=0.002 s, sync=0.000 s, total=0.391 s; sync files=1, longest=0.000 s, average=0.000 s
2014-10-23 14:52:09 CEST [25481]: [24-1] user=repmgr,db=repmgr LOG: duration: 403.777 ms
2014-10-23 14:52:11 CEST [25481]: [25-1] user=repmgr,db=repmgr LOG: statement: SELECT pg_tablespace_location(oid) spclocation FROM pg_tablespace WHERE spcname NOT IN ('pg_default', 'pg_global')
2014-10-23 14:52:11 CEST [25481]: [26-1] user=repmgr,db=repmgr LOG: duration: 0.514 ms
2014-10-23 14:52:12 CEST [25481]: [27-1] user=repmgr,db=repmgr LOG: statement: SELECT pg_xlogfile_name(pg_stop_backup())
2014-10-23 14:52:13 CEST [25481]: [28-1] user=repmgr,db=repmgr LOG: duration: 1005.802 ms
2014-10-23 14:52:13 CEST [25481]: [29-1] user=repmgr,db=repmgr LOG: disconnection: session time: 0:00:04.406 user=repmgr database=repmgr host=10.32.243.147 port=52477
2014-10-23 14:52:14 CEST [25524]: [1-1] user=[unknown],db=[unknown] LOG: connection received: host=10.32.243.147 port=52484
2014-10-23 14:52:14 CEST [25524]: [2-1] user=repmgr,db=[unknown] LOG: replication connection authorized: user=repmgr
```

### There is nothing new in pgpool after the new slave was configured

```bash
cz01-pgpool01 / # tail -f /var/log/local0
```

### Check the cluster status after failover

```bash
cz01-pgpool02 ~ # ssh postgres@cz01-psql02.example.com "/usr/pgsql-9.3/bin/repmgr --verbose -f /var/lib/pgsql/repmgr/repmgr.conf cluster show"
Warning: Permanently added 'cz01-psql02.example.com,10.32.243.148' (RSA) to the list of known hosts.

[2014-10-23 14:58:23] [INFO] repmgr connecting to database
Opening configuration file: /var/lib/pgsql/repmgr/repmgr.conf
Role | Connection String
 standby | host=cz01-psql01.example.com user=repmgr dbname=repmgr
* master | host=cz01-psql02.example.com user=repmgr dbname=repmgr
cz01-pgpool02 ~ # pcp_node_info 1 localhost 9898 admin password123 0
cz01-psql01.example.com 5432 3 0.500000
cz01-pgpool02 ~ # pcp_node_info 1 localhost 9898 admin password123 1
cz01-psql02.example.com 5432 1 0.500000
```

### Check if everything is working

```bash
cz01-pgpool02 ~ # psql --username=admin --dbname=postgres --host cz01-pgpool-ha.example.com -w -c "create database mydb"
CREATE DATABASE
cz01-pgpool02 ~ # psql --username=admin --dbname=postgres --host cz01-pgpool-ha.example.com -w -l | grep mydb
 mydb | admin | UTF8 | en_US.UTF-8 | en_US.UTF-8 |
cz01-pgpool02 ~ # psql --username=admin --dbname=postgres --host cz01-psql01.example.com -w -l | grep mydb
 mydb | admin | UTF8 | en_US.UTF-8 | en_US.UTF-8 |
cz01-pgpool02 ~ # psql --username=admin --dbname=postgres --host cz01-psql02.example.com -w -l | grep mydb
 mydb | admin | UTF8 | en_US.UTF-8 | en_US.UTF-8 |
```

### Reinitialize the slave in pgpool to be ready for read only queries

```bash
cz01-pgpool02 ~ # pcp_detach_node 0 localhost 9898 admin password123 0
cz01-pgpool02 ~ # pcp_attach_node 0 localhost 9898 admin password123 0
```

### logfile right after the slave was enabled for RO queries

```bash
cz01-pgpool01 / # cat /var/log/local0
...
2014-10-23T15:55:38.440946+02:00 cz01-pgpool01 pgpool[23264]: send_failback_request: fail back 0 th node request from pid 23264
2014-10-23T15:55:38.442034+02:00 cz01-pgpool01 pgpool[23257]: wd_start_interlock: start interlocking
2014-10-23T15:55:38.455732+02:00 cz01-pgpool01 pgpool[23257]: wd_assume_lock_holder: become a new lock holder
2014-10-23T15:55:38.459908+02:00 cz01-pgpool01 pgpool[23264]: wd_send_response: WD_STAND_FOR_LOCK_HOLDER received but lock holder exists already
2014-10-23T15:55:38.963952+02:00 cz01-pgpool01 pgpool[23257]: starting fail back. reconnect host cz01-psql01.example.com(5432)
2014-10-23T15:55:38.970549+02:00 cz01-pgpool01 pgpool[23257]: Do not restart children because we are failbacking node id 0 hostcz01-psql01.example.com port:5432 and we are in streaming replication mode
2014-10-23T15:55:38.974760+02:00 cz01-pgpool01 pgpool[23257]: find_primary_node_repeatedly: waiting for finding a primary node
2014-10-23T15:55:39.018890+02:00 cz01-pgpool01 pgpool[23257]: find_primary_node: primary node id is 1
2014-10-23T15:55:39.024830+02:00 cz01-pgpool01 pgpool[23257]: wd_end_interlock: end interlocking
2014-10-23T15:55:40.048487+02:00 cz01-pgpool01 pgpool[23257]: failover: set new primary node: 1
2014-10-23T15:55:40.048514+02:00 cz01-pgpool01 pgpool[23257]: failover: set new master node: 0
2014-10-23T15:55:40.048520+02:00 cz01-pgpool01 pgpool[23257]: failback done. reconnect host cz01-psql01.example.com(5432)
2014-10-23T15:55:40.050908+02:00 cz01-pgpool01 pgpool[26165]: worker process received restart request
2014-10-23T15:55:41.051525+02:00 cz01-pgpool01 pgpool[26164]: pcp child process received restart request
2014-10-23T15:55:41.056496+02:00 cz01-pgpool01 pgpool[23257]: PCP child 26164 exits with status 256 in failover()
2014-10-23T15:55:41.056543+02:00 cz01-pgpool01 pgpool[23257]: fork a new PCP child pid 1392 in failover()
2014-10-23T15:55:41.056565+02:00 cz01-pgpool01 pgpool[23257]: worker child 26165 exits with status 256
2014-10-23T15:55:41.057839+02:00 cz01-pgpool01 pgpool[23257]: fork a new worker child pid 1393
```

### Check pgpool stratus the slave should have a good value now

```bash
cz01-pgpool02 ~ # pcp_node_info 1 localhost 9898 admin password123 0
cz01-psql01.example.com 5432 1 0.500000
cz01-pgpool02 ~ # pcp_node_info 1 localhost 9898 admin password123 1
cz01-psql02.example.com 5432 1 0.500000
```

### Check if everything is working fine

```bash
cz01-pgpool02 ~ # psql --username=admin --dbname=postgres --host cz01-pgpool-ha.example.com -w -c "drop database mydb"
DROP DATABASE
cz01-pgpool02 ~ # psql --username=admin --dbname=postgres --host cz01-pgpool-ha.example.com -w -l | grep mydb
cz01-pgpool02 ~ # psql --username=admin --dbname=postgres --host cz01-psql01.example.com -w -l | grep mydb
cz01-pgpool02 ~ # psql --username=admin --dbname=postgres --host cz01-psql02.example.com -w -l | grep mydb
```

### Stop the master DB (original slave) - new master should be promoted

```bash
cz01-pgpool02 ~ # ssh cz01-psql02.example.com 'service postgresql-9.3 stop'
Warning: Permanently added 'cz01-psql02.example.com,10.32.243.148' (RSA) to the list of known hosts.

Stopping postgresql-9.3 service: [ OK ]
```

- Here is another example what may happen if original slave server, promoted to
new master fails. Again the slave is automatically promoted by pgpool to the new
master and "original master" (later slave) is master again. Changes are using
blue color in the diagram below.

![image](https://rawgithub.com/ruzickap/linux.xvx.cz/gh-pages/pics/postgresql_pgpool_repmgr/diagram_new_slave-original_master-become_master_again.svg)

### logs right after the master (original slave) was stopped

```bash
cz01-psql02 / # cat /var/lib/pgsql/9.3/data/pg_log/postgresql-Thu.log
...
2014-10-23 16:01:30 CEST [24133]: [6-1] user=,db= LOG: received fast shutdown request
2014-10-23 16:01:30 CEST [24133]: [7-1] user=,db= LOG: aborting any active transactions
2014-10-23 16:01:30 CEST [1991]: [7-1] user=admin,db=postgres FATAL: terminating connection due to administrator command
2014-10-23 16:01:30 CEST [1991]: [8-1] user=admin,db=postgres LOG: disconnection: session time: 0:02:13.805 user=admin database=postgres host=10.32.243.157 port=53988
2014-10-23 16:01:30 CEST [1986]: [7-1] user=admin,db=postgres FATAL: terminating connection due to administrator command
2014-10-23 16:01:30 CEST [1986]: [8-1] user=admin,db=postgres LOG: disconnection: session time: 0:02:19.271 user=admin database=postgres host=10.32.243.157 port=53982
2014-10-23 16:01:30 CEST [24145]: [2-1] user=,db= LOG: autovacuum launcher shutting down
2014-10-23 16:01:30 CEST [24142]: [37-1] user=,db= LOG: shutting down
2014-10-23 16:01:30 CEST [24142]: [38-1] user=,db= LOG: checkpoint starting: shutdown immediate
2014-10-23 16:01:30 CEST [24142]: [39-1] user=,db= LOG: checkpoint complete: wrote 1 buffers (0.0%); 0 transaction log file(s) added, 0 removed, 0 recycled; write=0.002 s, sync=0.008 s, total=0.449 s; sync files=1, longest=0.008 s, average=0.008 s
2014-10-23 16:01:30 CEST [24142]: [40-1] user=,db= LOG: database system is shut down
2014-10-23 16:01:31 CEST [25524]: [3-1] user=repmgr,db=[unknown] LOG: disconnection: session time: 1:09:17.350 user=repmgr database= host=10.32.243.147 port=52484
```

### Logs from pgpool01 after the master was stopped

```bash
cz01-pgpool01 / # cat /var/log/local0
...
2014-10-23T16:01:33.199817+02:00 cz01-pgpool01 pgpool[23257]: connect_inet_domain_socket: getsockopt() detected error: Connection refused
2014-10-23T16:01:33.200803+02:00 cz01-pgpool01 pgpool[23257]: make_persistent_db_connection: connection to cz01-psql02.example.com(5432) failed
2014-10-23T16:01:33.200989+02:00 cz01-pgpool01 pgpool[23257]: health check failed. 1 th host cz01-psql02.example.com at port 5432 is down
2014-10-23T16:01:33.201148+02:00 cz01-pgpool01 pgpool[23257]: set 1 th backend down status
2014-10-23T16:01:33.201280+02:00 cz01-pgpool01 pgpool[23257]: wd_start_interlock: start interlocking
2014-10-23T16:01:33.207742+02:00 cz01-pgpool01 pgpool[23264]: wd_send_response: WD_STAND_FOR_LOCK_HOLDER received it
2014-10-23T16:01:33.213943+02:00 cz01-pgpool01 pgpool[23264]: wd_send_response: failover request from other pgpool is canceled because it's while switching
2014-10-23T16:01:33.229107+02:00 cz01-pgpool01 pgpool[1393]: connect_inet_domain_socket: getsockopt() detected error: Connection refused
2014-10-23T16:01:33.229133+02:00 cz01-pgpool01 pgpool[1393]: make_persistent_db_connection: connection to cz01-psql02.example.com(5432) failed
2014-10-23T16:01:33.233566+02:00 cz01-pgpool01 pgpool[1393]: check_replication_time_lag: could not connect to DB node 1, check sr_check_user and sr_check_password
2014-10-23T16:01:33.716568+02:00 cz01-pgpool01 pgpool[23257]: starting degeneration. shutdown host cz01-psql02.example.com(5432)
2014-10-23T16:01:33.716597+02:00 cz01-pgpool01 pgpool[23257]: Restart all children
2014-10-23T16:01:36.720365+02:00 cz01-pgpool01 pgpool[23257]: find_primary_node_repeatedly: waiting for finding a primary node
2014-10-23T16:01:36.735887+02:00 cz01-pgpool01 pgpool[23257]: find_primary_node: primary node id is 0
2014-10-23T16:01:36.736038+02:00 cz01-pgpool01 pgpool[23257]: wd_end_interlock: end interlocking
2014-10-23T16:01:37.243499+02:00 cz01-pgpool01 pgpool[23257]: failover: set new primary node: 0
2014-10-23T16:01:37.243536+02:00 cz01-pgpool01 pgpool[23257]: failover: set new master node: 0
2014-10-23T16:01:37.332464+02:00 cz01-pgpool01 pgpool[1393]: worker process received restart request
2014-10-23T16:01:37.335636+02:00 cz01-pgpool01 pgpool[23257]: failover done. shutdown host cz01-psql02.example.com(5432)
2014-10-23T16:01:38.338656+02:00 cz01-pgpool01 pgpool[1392]: pcp child process received restart request
2014-10-23T16:01:38.345478+02:00 cz01-pgpool01 pgpool[23257]: PCP child 1392 exits with status 256 in failover()
2014-10-23T16:01:38.345510+02:00 cz01-pgpool01 pgpool[23257]: fork a new PCP child pid 2517 in failover()
2014-10-23T16:01:38.345516+02:00 cz01-pgpool01 pgpool[23257]: worker child 1393 exits with status 256
2014-10-23T16:01:38.345899+02:00 cz01-pgpool01 pgpool[23257]: fork a new worker child pid 2518
```

### Logs from psql01 after the master was stopped

```bash
cz01-psql01 / # cat /var/lib/pgsql/9.3/data/pg_log/postgresql-Thu.log
...
2014-10-23 16:01:31 CEST [26708]: [2-1] user=,db= LOG: replication terminated by primary server
2014-10-23 16:01:31 CEST [26708]: [3-1] user=,db= DETAIL: End of WAL reached on timeline 1 at 0/64000090.
2014-10-23 16:01:31 CEST [26708]: [4-1] user=,db= FATAL: could not send end-of-streaming message to primary: no COPY in progress
2014-10-23 16:01:31 CEST [26707]: [5-1] user=,db= LOG: record with zero length at 0/64000090
```

### Check status

```bash
cz01-pgpool02 ~ # ssh -q postgres@cz01-psql01.example.com "/usr/pgsql-9.3/bin/repmgr --verbose -f /var/lib/pgsql/repmgr/repmgr.conf cluster show"
[2014-10-23 16:05:16] [INFO] repmgr connecting to database
Opening configuration file: /var/lib/pgsql/repmgr/repmgr.conf
Role | Connection String
* master | host=cz01-psql01.example.com user=repmgr dbname=repmgr
 FAILED | host=cz01-psql02.example.com user=repmgr dbname=repmgr
[2014-10-23 16:05:16] [ERROR] Connection to database failed: could not connect to server: Connection refused
 Is the server running on host "cz01-psql02.example.com" (10.32.243.148) and accepting
 TCP/IP connections on port 5432?
```

### Check the functionality

```bash
cz01-pgpool02 ~ # psql --username=admin --dbname=postgres --host cz01-pgpool-ha.example.com -w -c "drop database mydb"
DROP DATABASE
cz01-pgpool02 ~ # psql --username=admin --dbname=postgres --host cz01-pgpool-ha.example.com -w -l | grep mydb
cz01-pgpool02 ~ # psql --username=admin --dbname=postgres --host cz01-psql01.example.com -w -l | grep mydb
```

### Reinitialize the stopped master to be slave again

```bash
cz01-pgpool02 ~ # ssh cz01-psql02.example.com 'service postgresql-9.3 stop; su - postgres -c "repmgr -D /var/lib/pgsql/9.3/data -d repmgr -p 5432 -U repmgr -R postgres --verbose --force standby clone cz01-psql01.example.com"; service postgresql-9.3 start;'
Warning: Permanently added 'cz01-psql02.example.com,10.32.243.148' (RSA) to the list of known hosts.

Stopping postgresql-9.3 service: [ OK ]
[2014-10-23 16:07:11] [ERROR] Did not find the configuration file './repmgr.conf', continuing
[2014-10-23 16:07:11] [NOTICE] repmgr Destination directory /var/lib/pgsql/9.3/data provided, try to clone everything in it.
[2014-10-23 16:07:11] [INFO] repmgr connecting to master database
[2014-10-23 16:07:11] [INFO] repmgr connected to master, checking its state
[2014-10-23 16:07:11] [INFO] Successfully connected to primary. Current installation size is 188 MB
Warning: Permanently added 'cz01-psql01.example.com,10.32.243.147' (RSA) to the list of known hosts.

[2014-10-23 16:07:11] [NOTICE] Starting backup...
[2014-10-23 16:07:11] [WARNING] directory "/var/lib/pgsql/9.3/data" exists but is not empty
[2014-10-23 16:07:11] [INFO] standby clone: master control file '/var/lib/pgsql/9.3/data/global/pg_control'
[2014-10-23 16:07:11] [INFO] standby clone: master control file '/var/lib/pgsql/9.3/data/global/pg_control'
[2014-10-23 16:07:11] [INFO] rsync command line: 'rsync --archive --checksum --compress --progress --rsh=ssh --delete postgres@cz01-psql01.example.com:/var/lib/pgsql/9.3/data/global/pg_control /var/lib/pgsql/9.3/data/global'
Warning: Permanently added 'cz01-psql01.example.com,10.32.243.147' (RSA) to the list of known hosts.

receiving incremental file list
pg_control
 8192 100% 7.81MB/s 0:00:00 (xfer#1, to-check=0/1)

sent 102 bytes received 235 bytes 674.00 bytes/sec
total size is 8192 speedup is 24.31
[2014-10-23 16:07:12] [INFO] standby clone: master data directory '/var/lib/pgsql/9.3/data'
[2014-10-23 16:07:12] [INFO] rsync command line: 'rsync --archive --checksum --compress --progress --rsh=ssh --delete --exclude=pg_xlog* --exclude=pg_log* --exclude=pg_control --exclude=*.pid postgres@cz01-psql01.example.com:/var/lib/pgsql/9.3/data/* /var/lib/pgsql/9.3/data'
Warning: Permanently added 'cz01-psql01.example.com,10.32.243.147' (RSA) to the list of known hosts.

receiving incremental file list
backup_label
 222 100% 216.80kB/s 0:00:00 (xfer#1, to-check=1239/1241)
backup_label.old
 222 100% 216.80kB/s 0:00:00 (xfer#2, to-check=1238/1241)
recovery.done
 102 100% 99.61kB/s 0:00:00 (xfer#3, to-check=1232/1241)
base/
base/1/
base/1/pg_internal.init
 116404 100% 155.93kB/s 0:00:00 (xfer#4, to-check=1225/1490)
base/12896/
base/12896/pg_internal.init
 116404 100% 153.41kB/s 0:00:00 (xfer#5, to-check=804/1542)
base/16386/
base/16386/pg_internal.init
 116404 100% 151.97kB/s 0:00:00 (xfer#6, to-check=559/1542)
base/16413/
base/16413/pg_internal.init
 116404 100% 150.56kB/s 0:00:00 (xfer#7, to-check=301/1542)
deleting pg_stat/global.stat
deleting pg_stat/db_16413.stat
deleting pg_stat/db_16386.stat
deleting pg_stat/db_12896.stat
deleting pg_stat/db_1.stat
deleting pg_stat/db_0.stat
global/
global/12789
 8192 100% 7.81MB/s 0:00:00 (xfer#8, to-check=30/1542)
global/12791
 16384 100% 15.62MB/s 0:00:00 (xfer#9, to-check=27/1542)
global/12792
 16384 100% 15.62MB/s 0:00:00 (xfer#10, to-check=26/1542)
global/12892
 8192 100% 7.81MB/s 0:00:00 (xfer#11, to-check=17/1542)
global/12894
 16384 100% 15.62MB/s 0:00:00 (xfer#12, to-check=16/1542)
global/12895
 16384 100% 5.21MB/s 0:00:00 (xfer#13, to-check=15/1542)
global/pg_internal.init
 12784 100% 2.44MB/s 0:00:00 (xfer#14, to-check=13/1542)
pg_clog/0000
 8192 100% 1.56MB/s 0:00:00 (xfer#15, to-check=12/1542)
pg_notify/
pg_stat/
pg_stat_tmp/
pg_stat_tmp/db_0.stat
 2540 100% 310.06kB/s 0:00:00 (xfer#16, to-check=6/1542)
pg_stat_tmp/db_1.stat
 1864 100% 227.54kB/s 0:00:00 (xfer#17, to-check=5/1542)
pg_stat_tmp/db_12896.stat
 3047 100% 371.95kB/s 0:00:00 (xfer#18, to-check=4/1542)
pg_stat_tmp/db_16386.stat
 4230 100% 458.98kB/s 0:00:00 (xfer#19, to-check=3/1542)
pg_stat_tmp/db_16413.stat
 6089 100% 660.70kB/s 0:00:00 (xfer#20, to-check=2/1542)
pg_stat_tmp/global.stat
 1026 100% 100.20kB/s 0:00:00 (xfer#21, to-check=1/1542)

sent 5452 bytes received 93077 bytes 65686.00 bytes/sec
total size is 198017139 speedup is 2009.73
[2014-10-23 16:07:13] [INFO] standby clone: master config file '/var/lib/pgsql/9.3/data/postgresql.conf'
[2014-10-23 16:07:13] [INFO] rsync command line: 'rsync --archive --checksum --compress --progress --rsh=ssh --delete postgres@cz01-psql01.example.com:/var/lib/pgsql/9.3/data/postgresql.conf /var/lib/pgsql/9.3/data'
Warning: Permanently added 'cz01-psql01.example.com,10.32.243.147' (RSA) to the list of known hosts.

receiving incremental file list

sent 11 bytes received 80 bytes 60.67 bytes/sec
total size is 20561 speedup is 225.95
[2014-10-23 16:07:14] [INFO] standby clone: master hba file '/var/lib/pgsql/9.3/data/pg_hba.conf'
[2014-10-23 16:07:14] [INFO] rsync command line: 'rsync --archive --checksum --compress --progress --rsh=ssh --delete postgres@cz01-psql01.example.com:/var/lib/pgsql/9.3/data/pg_hba.conf /var/lib/pgsql/9.3/data'
Warning: Permanently added 'cz01-psql01.example.com,10.32.243.147' (RSA) to the list of known hosts.

receiving incremental file list

sent 11 bytes received 76 bytes 174.00 bytes/sec
total size is 4812 speedup is 55.31
[2014-10-23 16:07:14] [INFO] standby clone: master ident file '/var/lib/pgsql/9.3/data/pg_ident.conf'
[2014-10-23 16:07:14] [INFO] rsync command line: 'rsync --archive --checksum --compress --progress --rsh=ssh --delete postgres@cz01-psql01.example.com:/var/lib/pgsql/9.3/data/pg_ident.conf /var/lib/pgsql/9.3/data'
Warning: Permanently added 'cz01-psql01.example.com,10.32.243.147' (RSA) to the list of known hosts.

receiving incremental file list

sent 11 bytes received 78 bytes 178.00 bytes/sec
total size is 1636 speedup is 18.38
[2014-10-23 16:07:14] [NOTICE] Finishing backup...
NOTICE: pg_stop_backup complete, all required WAL segments have been archived
[2014-10-23 16:07:15] [INFO] repmgr requires primary to keep WAL files 000000010000000000000065 until at least 000000010000000000000065
[2014-10-23 16:07:15] [NOTICE] repmgr standby clone complete
[2014-10-23 16:07:15] [NOTICE] HINT: You can now start your postgresql server
[2014-10-23 16:07:15] [NOTICE] for example : pg_ctl -D /var/lib/pgsql/9.3/data start
Opening configuration file: ./repmgr.conf
Starting postgresql-9.3 service: [ OK ]
```

- Again - after the db administrator find out the cause why master went down he
needs to initialize the failed master as a slave (by running command above).

Then everything is like before the testing - original master/slave state. The
green color is used for showing up the changes in the diagram.

![image](https://rawgithub.com/ruzickap/linux.xvx.cz/gh-pages/pics/postgresql_pgpool_repmgr/diagram_make_original_slave-failed_master-to_become_slave_again.svg)

### Check cluster status after recovery

```bash
cz01-pgpool02 ~ # ssh -q postgres@cz01-psql02.example.com "/usr/pgsql-9.3/bin/repmgr --verbose -f /var/lib/pgsql/repmgr/repmgr.conf cluster show"
[2014-10-23 16:08:23] [INFO] repmgr connecting to database
Opening configuration file: /var/lib/pgsql/repmgr/repmgr.conf
Role | Connection String
* master | host=cz01-psql01.example.com user=repmgr dbname=repmgr
 standby | host=cz01-psql02.example.com user=repmgr dbname=repmgr
cz01-pgpool02 ~ # pcp_node_info 1 localhost 9898 admin password123 0
cz01-psql01.example.com 5432 1 0.500000
cz01-pgpool02 ~ # pcp_node_info 1 localhost 9898 admin password123 1
cz01-psql02.example.com 5432 3 0.500000
```

### Re-enable the slave to be able to receive read-only requests

```bash
cz01-pgpool02 ~ # pcp_detach_node 0 localhost 9898 admin password123 1
cz01-pgpool02 ~ # pcp_attach_node 0 localhost 9898 admin password123 1
```

### Logs right after reenabling the slave again

```bash
cz01-pgpool01 / # cat /var/log/local0
...
2014-10-23T16:09:06.675035+02:00 cz01-pgpool01 pgpool[23264]: send_failback_request: fail back 1 th node request from pid 23264
2014-10-23T16:09:06.675868+02:00 cz01-pgpool01 pgpool[23257]: wd_start_interlock: start interlocking
2014-10-23T16:09:06.691133+02:00 cz01-pgpool01 pgpool[23257]: wd_assume_lock_holder: become a new lock holder
2014-10-23T16:09:06.698706+02:00 cz01-pgpool01 pgpool[23264]: wd_send_response: WD_STAND_FOR_LOCK_HOLDER received but lock holder exists already
2014-10-23T16:09:07.200639+02:00 cz01-pgpool01 pgpool[23257]: starting fail back. reconnect host cz01-psql02.example.com(5432)
2014-10-23T16:09:07.205234+02:00 cz01-pgpool01 pgpool[23257]: Do not restart children because we are failbacking node id 1 hostcz01-psql02.example.com port:5432 and we are in streaming replication mode
2014-10-23T16:09:07.209510+02:00 cz01-pgpool01 pgpool[23257]: find_primary_node_repeatedly: waiting for finding a primary node
2014-10-23T16:09:07.225224+02:00 cz01-pgpool01 pgpool[23257]: find_primary_node: primary node id is 0
2014-10-23T16:09:07.228223+02:00 cz01-pgpool01 pgpool[23257]: wd_end_interlock: end interlocking
2014-10-23T16:09:08.244875+02:00 cz01-pgpool01 pgpool[23257]: failover: set new primary node: 0
2014-10-23T16:09:08.244902+02:00 cz01-pgpool01 pgpool[23257]: failover: set new master node: 0
2014-10-23T16:09:08.244908+02:00 cz01-pgpool01 pgpool[23257]: failback done. reconnect host cz01-psql02.example.com(5432)
2014-10-23T16:09:08.247112+02:00 cz01-pgpool01 pgpool[2518]: worker process received restart request
2014-10-23T16:09:09.248473+02:00 cz01-pgpool01 pgpool[2517]: pcp child process received restart request
2014-10-23T16:09:09.252461+02:00 cz01-pgpool01 pgpool[23257]: PCP child 2517 exits with status 256 in failover()
2014-10-23T16:09:09.252492+02:00 cz01-pgpool01 pgpool[23257]: fork a new PCP child pid 3080 in failover()
2014-10-23T16:09:09.252499+02:00 cz01-pgpool01 pgpool[23257]: worker child 2518 exits with status 256
2014-10-23T16:09:09.253362+02:00 cz01-pgpool01 pgpool[23257]: fork a new worker child pid 3081
```

### Final cluster status verification

```bash
cz01-pgpool02 ~ # ssh -q postgres@cz01-psql02.example.com "/usr/pgsql-9.3/bin/repmgr --verbose -f /var/lib/pgsql/repmgr/repmgr.conf cluster show"
[2014-10-23 16:10:33] [INFO] repmgr connecting to database
Opening configuration file: /var/lib/pgsql/repmgr/repmgr.conf
Role | Connection String
* master | host=cz01-psql01.example.com user=repmgr dbname=repmgr
 standby | host=cz01-psql02.example.com user=repmgr dbname=repmgr
cz01-pgpool02 ~ # pcp_node_info 1 localhost 9898 admin password123 0
cz01-psql01.example.com 5432 1 0.500000
cz01-pgpool02 ~ # pcp_node_info 1 localhost 9898 admin password123 1
cz01-psql02.example.com 5432 1 0.500000
```

Huuh... It was a lot of copy & paste work. Anyway it's here if somebody needs it
;-)
