---
title: How to get HP enclosure c7000 information without ssh
author: Petr Ruzicka
date: 2013-08-23
description: How to get HP enclosure c7000 information without ssh
categories: [Linux, linux.xvx.cz]
tags: [hp-server, bash]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2013/08/how-to-get-hp-enclosure-c7000.html)
{: .prompt-info }

In the past few days I was doing some scripting to get the details about the
[HP BladeSystem c7000][c7000].

[c7000]: https://web.archive.org/web/20130919051544/http://h18004.www1.hp.com/products/blades/components/enclosures/c-class/c7000/

You can do a lot through SSH access, but I prefer to get the data without
setting up ssh keys or doing some expect scripts. I needed "showAll" output
and some nice structured XML file containing the hardware description, MACs,
WWIDs, etc...

Maybe it can be useful for some people who want to do the same - here is
the example:

```bash
#!/bin/bash -x

IP="10.29.33.14"
USER="admin"
PASSWORD="admin"
DESTINATION="./log_directory/"
WGET="wget --no-proxy --user=$USER --password=$PASSWORD --no-check-certificate"

cat > /tmp/hpoa.xml << EOF
<?xml version="1.0"?>
  <SOAP-ENV:Envelope xmlns:SOAP-ENV="http://www.w3.org/2003/05/soap-envelope" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:hpoa="hpoa.xsd">
    <SOAP-ENV:Body>
      <hpoa:userLogIn>
        <hpoa:username>$USER</hpoa:username>
        <hpoa:password>$PASSWORD</hpoa:password>
      </hpoa:userLogIn>
    </SOAP-ENV:Body>
  </SOAP-ENV:Envelope>
EOF

OASESSIONKEY=`curl --noproxy '*' --silent --data @/tmp/hpoa.xml --insecure https://$IP/hpoa | sed -n 's@.*<hpoa:oaSessionKey>\(.*\)</hpoa:oaSessionKey>.*@\1@p'`
curl --noproxy '*' --cookie "encLocalKey=$OASESSIONKEY; encLocalUser=$USER" --insecure https://$IP/cgi-bin/showAll -o $DESTINATION/$IP-showAll
curl --noproxy '*' --cookie "encLocalKey=$OASESSIONKEY; encLocalUser=$USER" --insecure https://$IP/cgi-bin/getConfigScript -o $DESTINATION/$IP-getConfigScript

$WGET https://$IP/xmldata?item=all -O $DESTINATION/$IP.xml
```

Enjoy :-)
