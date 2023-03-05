---
title: Transfer photos wirelessly from Sony cameras
author: Petr Ruzicka
date: 2023-01-15
description: Run FTP server for transferring photos from Sony cameras
categories: [Photography, Cameras]
tags: [settings, photo, ftp, cameras, wireless]
mermaid: true
image:
  path: /assets/img/posts/2022/2022-09-02-my-sony-a7-iv-settings/Sony_A7_IV_(ILCE-7M4)_-_by_Henry_Söderlund_(51739988735).avif
  alt: Sony A7 IV (ILCE-7M4) by Henry Söderlund
---

FTP is protocol which I haven't used for many years. I configured FTP
servers like [vsftpd](https://security.appspot.com/vsftpd.html) or
[ProFTPD](http://www.proftpd.org/) in the past, but this time I decided to look
at the [SFTPGo](https://github.com/drakkan/sftpgo).

![SFTPGo](https://raw.githubusercontent.com/drakkan/sftpgo/5d7f6960f30fc4ba9606d5569dddf8bf5b4764bb/static/img/logo.png
"SFTPGo")

The main reason why I wanted to run own FTP server on my laptop is to transfer
photos from my camera [Sony A7 IV](https://en.wikipedia.org/wiki/Sony_%CE%B17_IV)
wirelessly (no cables / SD card swapping).

## SFTPGo

Let's look at the way how you can run the FTP server on MacOS:

Install [SFTPGo](https://github.com/drakkan/sftpgo):

```bash
brew install sftpgo
```

Create `test` user and set admin account:

```bash
sftpgo resetprovider --force --config-dir /usr/local/var/sftpgo

cat > /tmp/sftpgo-initprovider-data.json << EOF
{
  "users": [
    {
      "id": 1,
      "status": 1,
      "username": "test",
      "password": "test123",
      "home_dir": "${HOME}/Pictures/ftp",
      "uid": 501,
      "gid": 20,
      "permissions": {
        "/": [
          "*"
        ]
      }
    }
  ],
  "folders": [],
  "admins": [
    {
      "id": 1,
      "status": 1,
      "username": "admin",
      "password": "admin123",
      "permissions": [
        "*"
      ]
    }
  ]
}
EOF

sftpgo initprovider --config-dir /usr/local/var/sftpgo --loaddata-from /tmp/sftpgo-initprovider-data.json
```

Configure [SFTPGo](https://github.com/drakkan/sftpgo):

```bash
cat > /usr/local/etc/sftpgo/sftpgo.json << EOF
{
  "ftpd": {
    "bindings": [
      {
        "port": 21
      }
    ]
  },
  "httpd": {
    "bindings": [
      {
        "port": 7999
      }
    ]
  },
  "sftpd": {
    "bindings": [
      {
        "port": 0
      }
    ]
  }
}
EOF

sudo brew services restart sftpgo
```

Restart the [SFTPGo](https://github.com/drakkan/sftpgo):

```bash
sudo brew services restart sftpgo
```

You can check the WebAdmin interface to see the details about created user:
`http://127.0.0.1:8080/web/admin/users`

![SFTPGo WebAdmin User](/assets/img/posts/2023/2023-01-15-ftp-and-sony-camera/sftpgo-webadmin-user.avif)
_SFTPGo WebAdmin User_

![SFTPGo WebAdmin Users](/assets/img/posts/2023/2023-01-15-ftp-and-sony-camera/sftpgo-webadmin-users.avif)
_SFTPGo WebAdmin Users_

## Sony Camera FTP + WiFi settings

Now you need to configure the Sony camera (Sony A7 IV) and connect it to the
WiFi + Configure FTP Transfer.

- Configure Wi-Fi connection to you Access Point / wireless router (or you can create
  [Personal Hotspot](https://support.apple.com/en-us/HT204023) on your iPhone
  like I did):

  ```mermaid
  flowchart LR
      A1[Network] --> A2(Wi-Fi) --> A3(Access Point Set.) --> A4(...your WiFi AP...)
  ```

  ![Sony A7 IV WiFi AP Configuration](/assets/img/posts/2023/2023-01-15-ftp-and-sony-camera/sony-camera-01-wifi-ap-configuration.avif){:width="550"}
  _Sony A7 IV WiFi AP Configuration_

> Make sure your Mac is connected to the same WiFi as your Sony camera
{: .prompt-warning }

- Find your local IP address on the Mac by running the `ifconfig` command in the
[terminal](https://support.apple.com/guide/terminal/open-or-quit-terminal-apd5265185d-f365-44cb-8b09-71a064a42125/mac):

  ```bash
  ❯ ifconfig en0
  ...
    inet 172.20.10.4 netmask ...
  ...
  ```

- Configure FTP:

  ```mermaid
  flowchart LR
      A1[Network] --> A2(Transfer/Remote) --> A3(FTP Transfer Func) --> A4(Server Setting) --> A5(Server 1)
        A5 --> B1(Display Name) --> B2(SFTPGo)
        A5 --> C1(Destination Settings) --> C2(Hostname) --> C3(172.20.10.4)
          C1 --> D1(Port) --> D2(21)
        A5 --> E1(User Info Setting) --> E2(User) --> E3(test)
          E1 --> F1(Password) --> F2(test123)
  ```

- Enable FTP:

  ```mermaid
  flowchart LR
      A1[Network] --> A2(Transfer/Remote) --> A3(FTP Transfer Func) --> A4(FTP Function)   --> A5(On)
      B1[Network] --> B2(Transfer/Remote) --> B3(FTP Transfer Func) --> B4(FTP Power Save) --> B5(On)
  ```

  ![Sony A7 IV FTP Configuration](/assets/img/posts/2023/2023-01-15-ftp-and-sony-camera/sony-camera-02-ftp-configuration.avif){:width="550"}
  _Sony A7 IV FTP Configuration_

- Initiate FTP transfer (copy photos from your camera to your Mac):

  ```mermaid
  flowchart LR
      A1[Network] --> A2(Transfer/Remote) --> A3(FTP Transfer Func) --> A4(FTP Transfer) --> A5(OK)
  ```

  ![Sony A7 IV FTP Transfer](/assets/img/posts/2023/2023-01-15-ftp-and-sony-camera/sony-camera-03-ftp-transfer.avif){:width="550"}
  _Sony A7 IV FTP Transfer_

The camera configuration including WiFi configuration, FTP, and photo transfer
can be found [here](https://youtu.be/TAH83ezrxbU):

{% include embed/youtube.html id='TAH83ezrxbU' %}

Enjoy ... 😉
