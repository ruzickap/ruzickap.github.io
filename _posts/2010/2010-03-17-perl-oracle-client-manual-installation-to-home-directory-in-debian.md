---
title: Perl Oracle client manual installation to home directory in Debian
author: Petr Ruzicka
date: 2010-03-17
categories: [Linux, Debian]
tags: [perl, Oracle, database]
---

I need to connect to the Oracle database in my work to get some data from it.
I'm not the Oracle expert, but I decided to use
[DBD::Oracle](http://search.cpan.org/~pythian/DBD-Oracle/).

Most of the manuals and how-to pages describe, how to install client libraries
to system (usually as root), which was not my case.

I just need one directory with libraries in my $HOME and a few scripts to get
some data from the database - no system installations.

Here are the steps how to install DBD-Oracle and its libraries to "one"
directory without making a mess in the system:

First let's install core system related libraries and tools

```bash
aptitude install gcc libdbi-perl libaio1 libstdc++6-4.4-dev unzip
```

Get the Oracle client libraries from the Oracle Instant Client download page:

```bash
mkdir $HOME/lib/ && cd $HOME/lib/
wget basiclite-11.1.0.7.0-linux-x86_64.zip sqlplus-11.1.0.7.0-linux-x86_64.zip sdk-11.1.0.7.0-linux-x86_64.zip
unzip *.zip
```

Install [DBD::Oracle](http://search.cpan.org/~pythian/DBD-Oracle/):

```bash
wget http://search.cpan.org/CPAN/authors/id/P/PY/PYTHIAN/DBD-Oracle-1.24a.tar.gz
tar xvzf DBD-Oracle*.tar.gz
cd DBD-Oracle*

export LD_LIBRARY_PATH=$HOME/lib/instantclient_11_1
export C_INCLUDE_PATH=$HOME/lib/instantclient_11_1/sdk/include

perl Makefile.PL PREFIX=$HOME/lib
make && make install
```

Now you should have DBD::Oracle installed in your $HOME/lib directory.

You can modify this short script to see if it's really working:

```perl
#!/usr/bin/perl -w
use DBI;

push (@INC,"$ENV{'HOME'}/lib/lib/perl/5.10.1");

$host="myhost";
$user="ORACLEUSER";
$passwd='MYPASS';

#tnsping
#lsnrctl services - to find right sid

$dbh = DBI->connect("dbi:Oracle:host=$host;sid=ORCH3;port=1521", $user, $passwd);
  or die "Couldn't connect to database: " . DBI->errstr;

my $sth = $dbh->prepare("select * from tab")
  or die "Couldn't prepare statement: " . $dbh->errstr;

$sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
while (my ($table_name) = $sth->fetchrow_array()) {
    print $table_name, "\n";
}
$sth->finish();
$dbh->disconnect();
```

I believe you can install DBD::Oracle without dependencies above like gcc or
libstdc++, but I'm fine to install these.
