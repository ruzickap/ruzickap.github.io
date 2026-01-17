---
title: BOINC managed from command line - boinc_cmd
author: Petr Ruzicka
date: 2009-02-20
description: ""
categories: [Linux]
tags: [boinc, bash]
---

> <https://linux-old.xvx.cz/2009/02/boinc-managed-from-command-line-boinc_cmd/>
{: .prompt-info }

I installed [BOINC](https://boinc.berkeley.edu/) to my server to help the world
with scientific problems. It's really easy to install it from repositories of
various distributions, but it's not so easy to configure it.

Usually you can use [BOINC manager](https://en.wikipedia.org/wiki/Boinc) to
configure BOINC. Unfortunately it is graphical application and it uses **port
31416** to connect to local/remote BOINC installations.

For obvious reasons you don't want to install GUI applications on servers and
you also don't want to enable ports on firewall.

That's time for `boinc_cmd` and here are a few tips on how to use it.

- Set ***http proxy*** 10.226.56.40:3128:

  ```bash
  boinc_cmd --passwd my_password --set_proxy_settings 10.226.56.40 3128 "" "" "" "" "" "" ""
  ```

- Count all the time:

  ```bash
  boinc_cmd --passwd my_password --set_run_mode always
  ```

- Don't get more work:

  ```bash
  boinc_cmd --passwd my_password --project http://abcathome.com/ nomorework
  ```

- Attach to the project:

  ```bash
  boinc_cmd --passwd my_password --project_attach http://abcathome.com/  project_id
  ```

- Update project preferences:

  ```bash
  boinc_cmd --passwd my_password --project http://abcathome.com/ update
  ```
