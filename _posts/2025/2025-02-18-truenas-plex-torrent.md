---
title: TrueNAS CE 25.04 with Plex and qBittorrent
author: Petr Ruzicka
date: 2025-02-18
description: Install TrueNAS Community Edition 25.04 with Plex and qBittorrent
categories: [ qbittorrent, plex, truenas ]
mermaid: true
tags: [ qbittorrent, plex, truenas ]
image: https://raw.githubusercontent.com/truenas/documentation/3abfe90c0491c6944d0608c8913b596b03d2678a/static/images/TrueNAS_Community_Edition.png
---

I had the opportunity to test the [Dell OptiPlex 3000 Thin Client](https://www.dell.com/en-us/shop/cty/pdp/spd/optiplex-3000-thin-client)
with TrueNAS Community Edition 25.04. The machine is equipped with 2 CPUs,
8GB of RAM, and 64GB of eMMC storage.

🕹️ Recorded screen cast:

{% include embed/youtube.html id='-UY4ecm4X4k' %}

## Installation

![TrueNAS](https://raw.githubusercontent.com/truenas/documentation/3abfe90c0491c6944d0608c8913b596b03d2678a/static/images/TrueNAS_Community_Edition.png){:width="400"}

Put the [TrueNAS CE 25.04 ISO](https://www.truenas.com/download-truenas-scale/)
on a USB stick using [balenaEtcher](https://etcher.balena.io/).

> Make sure to disable **Secure Boot** in the BIOS before proceeding.

Boot TrueNAS from the USB stick and follow these steps:

* Shell
  * Run commands:

    ```bash
    sed -i 's/-n3:0:0/-n3:0:+16G/' /usr/lib/python3/dist-packages/truenas_installer/install.py
    exit
    ```

* Install/Upgrade
* Select the disk to install TrueNAS (`mmcblk0`)
* Administrative user (truenas_admin)
* ...

Links:

* [How to Install TrueNAS CORE on an SSD NVMe/SATA Partition and Reclaim Unused Boot-Pool Space](https://youtu.be/ZMSSE6FViak?si=b-sz-fPk6xwol0ea&t=50)
* [Install TrueNAS SCALE on a partition instead of the full disk](https://gist.github.com/gangefors/2029e26501601a99c501599f5b100aa6)

## Configuration

![TrueNAS](https://raw.githubusercontent.com/truenas/documentation/1bb5fd6adb68b18aad6476bcab61d46bad2f0e2e/static/images/truenas-logo-mark.png)

> The admin username for the TrueNAS WebUI is `truenas_admin`, and the password
> is the same as the root password set during the installation.

### [Settings](https://www.truenas.com/docs/scale/25.04/scaletutorials/systemsettings/)

Configure General Settings (GUI, Localization, and Email Settings), Advanced
Settings (Access), Services (SMB, SSH), and Shell (Create and Export pool):

```mermaid
graph LR
    subgraph truenas[TrueNAS]
      system[System] --> general_settings[General Settings]
      system --> advanced_settings[Advanced Settings]
      system --> services[Services]
      system --> shell[Shell]
    end
    subgraph general_settings_dashboard[General Settings]
      general_settings --> gui_settings[GUI Settings]
      gui_settings --> web_interface_http_https_redirect[Web Interface HTTP -> HTTPS Redirect]
      general_settings --> localization_settings[Localization Settings]
      localization_settings --> timezone[Timezone: Europe/Prague]
      general_settings --> email_settings[Email Settings]
      email_settings --> send_mail_method[Send Mail Method: GMail OAuth]
    end
    subgraph advanced_settings_dashboard[Advanced Settings]
      advanced_settings --> access_configure[Access Configure]
      access_configure --> session_timeout[Session Timeout: 30000]
    end
    subgraph services_dashboard[Services]
      services --> smb[SMB]
      services --> ssh[SSH]
    end
    subgraph shell_dashboard[Shell]
      shell --> commands[$ sudo su<br># sgdisk -n0:0:0 -t0:BF01 /dev/mmcblk0<br># partprobe<br># zpool create -f -R /mnt -O compression=lz4 -O atime=off my-local-disk-pool /dev/mmcblk0p4<br># zpool export my-local-disk-pool]
    end
    click general_settings "https://truenas.local/ui/system/general"
    click advanced_settings "https://truenas.local/ui/system/advanced"
    click services "https://truenas.local/ui/system/services"
    click shell "https://truenas.local/ui/system/shell"
    style commands text-align:left
```

### [Create and Import Storage pool](https://www.truenas.com/docs/scale/25.04/scaletutorials/storage/createpoolwizard/)

Import the previously created pool (`my-local-disk-pool`) and create a new pool
named `my-pool`:

```mermaid
graph LR
    subgraph truenas[TrueNAS]
      storage[Storage]
    end
    subgraph storage_dashboard[Storage Dashboard]
      storage --> import_pool[Import Pool]
      import_pool --> pool[Pool: my-local-disk-pool]
      storage --> create_pool[Create Pool]
      create_pool --> name[Name: my-pool<br>Layout: Stripe<br>]
    end
    click storage "https://truenas.local/ui/storage"
    click create_pool "https://truenas.local/ui/storage/create"
```

### [Create Dataset](https://www.truenas.com/docs/scale/25.04/scaletutorials/datasets/datasetsscale/)

Create the `data` dataset in the `my-pool` pool and the `plex` dataset in the
`my-local-disk-pool` storage pool, ensuring proper permissions are configured
for each:

```mermaid
graph LR
    subgraph truenas[TrueNAS]
      datasets[Datasets]
    end
    subgraph datasets_dashboard[Datasets]
      datasets --> dataset_name_my_pool[Dataset Name: my-pool]
      dataset_name_my_pool --> add_dataset_my_pool[Add Dataset]
      add_dataset_my_pool --> name_data[Name: data]
      add_dataset_my_pool --> dataset_preset_data[Dataset Preset -> SMB]
    end
    subgraph datasets_dashboard[Datasets]
      datasets --> dataset_name_my_local_disk_pool[Dataset Name: my-local-disk-pool]
      dataset_name_my_local_disk_pool --> add_dataset_my_local_disk_pool[Add Dataset]
      add_dataset_my_local_disk_pool --> name_data_plex[Name: plex]
      add_dataset_my_local_disk_pool --> dataset_preset_plex[Dataset Preset -> Apps]
    end
    click datasets "https://truenas.local/ui/datasets"
```

```mermaid
graph LR
    subgraph truenas[TrueNAS]
      datasets[Datasets]
    end
    subgraph datasets_dashboard[Datasets]
      datasets --> dataset_name[Dataset Name: my-pool -> data]
      dataset_name --> permissions[Permissions -> Edit]
    end
    subgraph edit_acl_dashboard[Edit ACL]
      permissions --> add_item["\+ Add Item"]
      add_item --> who[Who -> Group]
      add_item --> group[Group -> apps]
      add_item --> apply_permissions_recursively[Apply permissions recursively]
      add_item --> save_access_control_list[Save Access Control List]
    end
    click datasets "https://truenas.local/ui/datasets"
```

### [Configure Credentials](https://www.truenas.com/docs/scale/25.04/scaletutorials/credentials/backupcredentials/addcloudcredentials/)

Create a new user named `ruzickap`, and update the password and email address
for the existing `truenas_admin` user:

```mermaid
graph LR
    subgraph truenas[TrueNAS]
      credentials[Credentials] --> backup_credentials[Backup Credentials]
      credentials --> users[Users]
    end
    subgraph backup_credentials_dashboard[Backup Credentials]
      backup_credentials --> provider[Provider: Microsoft OneDrive]
      provider --> oauth_authentication[OAuth Authentication -> Log In To Provider]
      backup_credentials --> drives_list[Drives List -> OneDrive]
    end
    subgraph users_dashboard_[Users]
      users --> add[Add]
      add --> add_full_name[Full Name: Petr Ruzicka]
      add --> add_username[Username: ruzickap]
      add --> add_password[Password: my_password]
      add --> add_email[Email: petr.ruzicka\@gmail.com]
      add --> add_confirm_password[Confirm Password: my_password]
      add --> add_confirm_password_auxiliary_groups[Auxiliary Groups: builtin_administrators, docker]
      add --> add_home_directory[Home Directory: /mnt/my-local-disk-pool]
      add --> add_ssh_password_login_enabled[SSH password login enabled]
      add --> add_shell[Shell: bash]
      add --> add_allow_all_sudo_commands[Allow all sudo commands]
      add --> add_allow_all_sudo_commands_with_no_password[Allow all sudo commands with no password]
      add --> add_create_home_directory[Create Home Directory]
      users --> truenas_admin[truenas_admin]
      truenas_admin --> edit[Edit]
      edit --> edit_new_password[New Password: my_password]
      edit --> edit_email[Email: petr.ruzicka\@gmail.com]
      edit --> edit_confirm_new_password[Confirm New Password: my_password]
      edit --> edit_allow_all_sudo_commands_with_no_password[Allow all sudo commands with no password]
    end
    click users "https://truenas.local/ui/credentials/users"
    click backup_credentials "https://truenas.local/ui/credentials/backup-credentials"
```

### [Add Applications](https://www.truenas.com/docs/scale/25.04/scaleuireference/apps/)

Configure the applications to use the `my-local-disk-pool` pool as their
designated storage location:

```mermaid
graph LR
    subgraph truenas[TrueNAS]
      apps[Apps]
    end
    subgraph applications_installed_dashboard[Applications Installed]
      apps --> configuration[Configuration]
      configuration --> choose_pool[Choose Pool]
      choose_pool --> pool[Pool: my-local-disk-pool]
    end
    click apps "https://truenas.local/ui/apps/installed"
```

#### [OpenSpeedTest](https://openspeedtest.com/)

Install the [OpenSpeedTest](https://openspeedtest.com/) application to easily
measure network speed and performance:

![Open Speed Test](https://raw.githubusercontent.com/openspeedtest/Docker-Image/43006f052f08495881e3a63be13700954440bbb8/files/www/assets/images/icons/android-chrome-512x512.png){:width="100"}

```mermaid
graph LR
    subgraph truenas[TrueNAS]
      apps[Apps]
    end
    subgraph applications_installed_dashboard[Applications Installed]
      apps --> discover_apps[Discover Apps]
      discover_apps --> open_speed_test[Open Speed Test]
      open_speed_test --> install[Install]
    end
    click apps "https://truenas.local/ui/apps/installed"
```

Test the [OpenSpeedTest](https://openspeedtest.com/) web interface by accessing
it through the [local instance](http://truenas.local:30116/).

![SpeedTest by OpenSpeedTest](https://github.com/openspeedtest/v2-Test/raw/main/images/10G-S.gif){:width="500"}

#### [File Browser](https://filebrowser.org/)

Add the [File Browser](https://filebrowser.org/) application to manage files
easily through a user-friendly web interface:

![File Browser](https://raw.githubusercontent.com/filebrowser/filebrowser/7414ca10b3141853c89ecd752aa732d5755ff1bf/frontend/public/img/logo.svg){:width="100"}

```mermaid
graph LR
    subgraph truenas[TrueNAS]
      apps[Apps]
    end
    subgraph applications_installed_dashboard[Applications Installed]
      apps --> discover_apps[Discover Apps]
      discover_apps --> file_browser[File Browser]
      file_browser --> install[Install]
      install --> storage_configuration[Storage Configuration]
      storage_configuration --> additional_storage[Additional Storage -> Add]
      additional_storage --> data_storage_type[Type: Host Path]
      additional_storage --> mount_path[Mount Path: /data]
      additional_storage --> host_path[Host Path: /mnt/my-pool/data]
    end
    click apps "https://truenas.local/ui/apps/installed"
```

Test the [File Browser](https://filebrowser.org/) web interface by clicking the
[File Browser](http://truenas.local:30051/) link and using the following login
credentials:

* User: `admin`
* Password: `admin`

#### [qBittorrent](https://www.qbittorrent.org/)

Install the [qBittorrent](https://www.qbittorrent.org/) application to download
torrents:

![qBittorrent](https://raw.githubusercontent.com/qbittorrent/qBittorrent/ab91d546e51bdd104d6d520dc2a000ade79b207b/src/icons/qbittorrent-tray.svg){:width="100"}

```mermaid
graph LR
    subgraph truenas[TrueNAS]
      apps[Apps]
    end
    subgraph applications_installed_dashboard[Applications Installed]
      apps --> discover_apps[Discover Apps]
      discover_apps --> qbittorrent[qBittorrent]
      qbittorrent --> install[Install]
      install --> storage_configuration[Storage Configuration]
      storage_configuration --> qbittorrent_downloads_storage[qBittorrent Downloads Storage]
      qbittorrent_downloads_storage --> qbittorrent_configuration_storage_type[Type: Host Path]
      qbittorrent_downloads_storage --> qbittorrent_configuration_storage_mount_path[Host Path: /mnt/my-pool/data]
    end
    click apps "https://truenas.local/ui/apps/installed"
```

##### [qBittorrent](https://www.qbittorrent.org/) Configuration

It is necessary to configure qBittorrent to work properly with the configured
pools and datasets.

![qBittorrent](https://raw.githubusercontent.com/qbittorrent/qBittorrent/ab91d546e51bdd104d6d520dc2a000ade79b207b/src/icons/mascot.png)

Obtain the username and password for qBittorrent:

```mermaid
graph LR
    subgraph truenas[TrueNAS]
      apps[Apps]
    end
    subgraph applications_installed_dashboard[Applications Installed]
      apps --> qbittorrent[qbittorrent]
      qbittorrent --> workloads[Workloads]
      workloads --> qbittorrent_running[qbittorrent – Running]
      qbittorrent_running --> view_logs[View Logs]
      view_logs --> password[A temporary password is provided for this session: xxxxxx]
    end
    click apps "https://truenas.local/ui/apps/installed"
```

Access the [qBittorrent](http://truenas.local:30024/) web interface and log in
using the credentials obtained from the logs.

Click the **Options** icon (typically a gear symbol) at the top and configure
the following settings:

```mermaid
graph LR
    options[Options] --> downloads[Downloads]
    options[Options] --> webui[WebUI]
    downloads --> save_path[Delete .torrent files afterwards]
    downloads --> default_save_path[Default Save Path: /downloads/torrents]
    webui --> bypass[Bypass authentication for clients in whitelisted IP subnets: 192.168.1.0/24]
```

#### [Plex](https://www.plex.tv/)

Install the [Plex](https://www.plex.tv/) application for media streaming:

![Plex](https://raw.githubusercontent.com/plexinc/pms-docker/8db104bcc92596266bfc37f746b9fb923a890337/img/plex-server.png){:width="100"}

```mermaid
graph LR
    subgraph truenas[TrueNAS]
      apps[Apps]
    end
    subgraph applications_installed_dashboard[Applications Installed]
      apps --> discover_apps[Discover Apps]
      discover_apps --> plex[Plex]
      plex --> install[Install]
      install --> storage_configuration[Storage Configuration]
      storage_configuration --> plex_data_storage[Plex Data Storage]
      plex_data_storage --> plex_data_storage_type[Type: Host Path]
      plex_data_storage --> plex_data_storage_host_path[Host Path: /mnt/my-pool/data]
      storage_configuration --> plex_configuration_storage[Plex Configuration Storage]
      plex_configuration_storage --> plex_configuration_storage_type[Type: Host Path]
      plex_configuration_storage --> plex_configuration_storage_host_path[Host Path: /mnt/my-local-disk-pool/plex]
    end
    click apps "https://truenas.local/ui/apps/installed"
```

![Plex](https://raw.githubusercontent.com/plexinc/plex-media-player/3d4859f1b1b7aaa3a1be31699fc9cc9295662848/resources/images/splash.png){:width="200"}

### [Configure Data Protection](https://www.truenas.com/docs/scale/25.04/scaletutorials/dataprotection/cloudsynctasks/)

Configure Cloud Sync Tasks to back up Plex data to Microsoft OneDrive, and
schedule regular S.M.A.R.T. tests:

```mermaid
graph LR
    subgraph truenas[TrueNAS]
      data_protection[Data Protection]
    end
    subgraph data_protection_dashboard[Data Protection]
      data_protection --> cloud_sync_tasks[Cloud Sync Tasks -> Add]
      cloud_sync_tasks --> provider[Credentials: Microsoft OneDrive]
      provider --> what_and_when_direction[Direction: PUSH]
      provider --> what_and_when_directory_files[Directory/Files: /mnt/my-local-disk-pool/plex]
      provider --> what_and_when_folder[Folder: /truenas-backup-plex]
      provider --> what_and_when_schedule[Schedule: Weekly]
      data_protection --> periodic_smart_tests[Periodic S.M.A.R.T. Tests -> Add]
      periodic_smart_tests --> all_disks[All Disks]
      periodic_smart_tests --> type[Type: SHORT]
      periodic_smart_tests --> schedule[Schedule: Weekly]
    end
    click data_protection "https://truenas.local/ui/data-protection"
```

![TrueNAS](https://raw.githubusercontent.com/truenas/documentation/1bb5fd6adb68b18aad6476bcab61d46bad2f0e2e/static/images/full-rgb.png)

Enjoy ... 😉
