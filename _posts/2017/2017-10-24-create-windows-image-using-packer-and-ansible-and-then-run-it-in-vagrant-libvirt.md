---
title: Create Windows image using Packer and Ansible and then run it in Vagrant (libvirt)
author: Petr Ruzicka
date: 2017-10-24
description: Create Windows image using Packer and Ansible and then run it in Vagrant (libvirt)
categories: [Ansible, Virtualization]
tags: [qemu, winrm]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2017/10/create-windows-image-using-packer-and.html)
{: .prompt-info }

I saw many Packer templates which are used to build the Windows images on
Github. Almost all of them are using PowerShell scripts or DOS-style batch
files. Ansible can use WinRM to manage Windows for some time - therefore I
decided to use it also with Packer when building the images. Because of the
[bug](https://github.com/hashicorp/packer/issues/4773) it was not possible to
use Ansible 2.3 (or older) with Packer + WinRM.

The latest Ansible 2.4 is working fine with Packer + Qemu + WinRM when you want
to create the Windows images:
[https://www.packer.io/docs/provisioners/ansible.html#winrm-communicator](https://www.packer.io/docs/provisioners/ansible.html#winrm-communicator)

![HashiCorp Packer logo](https://raw.githubusercontent.com/hashicorp/packer/69c6852d57181f18f4d19b73d5979a7d001c2d43/website/public/img/logo-text.svg){:width="400"}

![Ansible logo](https://s3.amazonaws.com/media-p.slid.es/uploads/team-32/images/1859201/Ansible-Official-Logo-Black.svg){:width="200"}

Let's see how you can do it in Fedora 26:

- Packer + with [WinRM communicator](https://www.packer.io/docs/provisioners/ansible.html#winrm-communicator)
/ Ansible / Qemu and enable Packer's Winrm communicator

  ```bash
  # Install necessary packages
  dnf install -y -q ansible qemu-img qemu-kvm wget unzip

  # Download and unpack Packer
  cd /tmp || exit
  wget https://releases.hashicorp.com/packer/1.1.3/packer_1.1.3_linux_amd64.zip
  unzip packer*.zip

  # Use packerio as a binary name, because packer binary already exists in fedora : /usr/sbin/packer as part of cracklib-dicts package
  mv packer /usr/local/bin/packerio

  # Install WinRM communicator for Packer (https://www.packer.io/docs/provisioners/ansible.html#winrm-communicator)
  mkdir -p ~/.ansible/plugins/connection_plugins
  wget -P ~/.ansible/plugins/connection_plugins/ https://raw.githubusercontent.com/hashicorp/packer/master/test/fixtures/provisioner-ansible/connection_plugins/packer.py
  sed -i.orig 's@#connection_plugins =.*@connection_plugins = ~/.ansible/plugins/connection_plugins/@' /etc/ansible/ansible.cfg
  ```

- Create the Packer template, Autounattended file for Windows 2016, and a few
helper scripts

  ```bash
  # Prepare directory structure
  mkdir -p /var/tmp/packer_windows-server-2016-eval/{scripts/win-common,http/windows-server-2016,ansible}
  cd /var/tmp/packer_windows-server-2016-eval || exit

  # Download Autounattended file for Windows Server 2016 Evaluation
  wget -c -P http/windows-server-2016 https://raw.githubusercontent.com/ruzickap/packer-templates/master/http/windows-server-2016/Autounattend.xml

  # Create some basic Ansible playbook for Windows provisioning
  cat > ansible/win.yml << EOF
  ---
  - hosts: all

    tasks:
      - name: Enable Remote Desktop
        win_regedit:
          key: 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
          value: fDenyTSConnections
          data: 0
          datatype: dword

      - name: Allow connections from computers running any version of Remote Desktop (less secure)
        win_regedit:
          key: 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
          value: UserAuthentication
          data: 0
          datatype: dword

      - name: Allow RDP traffic
        win_shell: Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
  EOF

  # Get scripts which helps during Autounattended installation + executed after Ansible
  wget -c -P scripts/win-common https://raw.githubusercontent.com/ruzickap/packer-templates/master/scripts/win-common/{fixnetwork.ps1,remove_nic.bat}

  # Get the Packer template
  wget -c https://raw.githubusercontent.com/ruzickap/packer-templates/master/{windows-server-2016-eval.json,Vagrantfile-windows.template}
  ```

- Download and mount the virtio-win iso and run Packer

  ```bash
  VIRTIO_WIN_ISO_DIR=$(mktemp -d --suffix=_virtio-win-iso)
  export VIRTIO_WIN_ISO_DIR
  export NAME=windows-server-2016-standard-x64-eval
  export WINDOWS_VERSION=2016
  export WINDOWS_TYPE=server
  export TMPDIR="/var/tmp/"

  cd /var/tmp/packer_windows-server-2016-eval || exit

  # Download and mount virtio-win to provide basic virtio Windows drivers
  wget -c https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso
  mount -o loop virtio-win.iso "$VIRTIO_WIN_ISO_DIR"

  # Build image with packer
  /usr/local/bin/packerio build windows-server-2016-eval.json

  umount "$VIRTIO_WIN_ISO_DIR"
  rmdir "$VIRTIO_WIN_ISO_DIR"
  ```

Complete build log:

```console
[root@localhost packer_windows-server-2016-eval]# /usr/local/bin/packerio build windows-server-2016-eval.json
windows-server-2016-standard-x64-eval output will be in this color.

==> windows-server-2016-standard-x64-eval: Downloading or copying ISO
windows-server-2016-standard-x64-eval: Downloading or copying: http://care.dlservice.microsoft.com/dl/download/1/4/9/149D5452-9B29-4274-B6B3-5361DBDA30BC/14393.0.161119-1705.RS1_REFRESH_SERVER_EVAL_X64FRE_EN-US.ISO
==> windows-server-2016-standard-x64-eval: Creating floppy disk...
windows-server-2016-standard-x64-eval: Copying files flatly from floppy_files
windows-server-2016-standard-x64-eval: Copying file: http/windows-server-2016/Autounattend.xml
windows-server-2016-standard-x64-eval: Copying file: scripts/win-common/fixnetwork.ps1
windows-server-2016-standard-x64-eval: Copying file: /tmp/tmp.cQYclNvngg_virtio-win-iso/NetKVM/2k16/amd64/netkvm.cat
windows-server-2016-standard-x64-eval: Copying file: /tmp/tmp.cQYclNvngg_virtio-win-iso/NetKVM/2k16/amd64/netkvm.inf
windows-server-2016-standard-x64-eval: Copying file: /tmp/tmp.cQYclNvngg_virtio-win-iso/NetKVM/2k16/amd64/netkvm.sys
windows-server-2016-standard-x64-eval: Copying file: /tmp/tmp.cQYclNvngg_virtio-win-iso/NetKVM/2k16/amd64/netkvmco.dll
windows-server-2016-standard-x64-eval: Copying file: /tmp/tmp.cQYclNvngg_virtio-win-iso/qxldod/2k16/amd64/qxldod.cat
windows-server-2016-standard-x64-eval: Copying file: /tmp/tmp.cQYclNvngg_virtio-win-iso/qxldod/2k16/amd64/qxldod.inf
windows-server-2016-standard-x64-eval: Copying file: /tmp/tmp.cQYclNvngg_virtio-win-iso/qxldod/2k16/amd64/qxldod.sys
windows-server-2016-standard-x64-eval: Copying file: /tmp/tmp.cQYclNvngg_virtio-win-iso/viostor/2k16/amd64/viostor.cat
windows-server-2016-standard-x64-eval: Copying file: /tmp/tmp.cQYclNvngg_virtio-win-iso/viostor/2k16/amd64/viostor.inf
windows-server-2016-standard-x64-eval: Copying file: /tmp/tmp.cQYclNvngg_virtio-win-iso/viostor/2k16/amd64/viostor.sys
windows-server-2016-standard-x64-eval: Done copying files from floppy_files
windows-server-2016-standard-x64-eval: Collecting paths from floppy_dirs
windows-server-2016-standard-x64-eval: Resulting paths from floppy_dirs : []
windows-server-2016-standard-x64-eval: Done copying paths from floppy_dirs
==> windows-server-2016-standard-x64-eval: Creating hard drive...
==> windows-server-2016-standard-x64-eval: Found port for communicator (SSH, WinRM, etc): 2518.
==> windows-server-2016-standard-x64-eval: Looking for available port between 5900 and 6000 on 127.0.0.1
==> windows-server-2016-standard-x64-eval: Starting VM, booting from CD-ROM
windows-server-2016-standard-x64-eval: The VM will be run headless, without a GUI. If you want to
windows-server-2016-standard-x64-eval: view the screen of the VM, connect via VNC without a password to
windows-server-2016-standard-x64-eval: vnc://127.0.0.1:5900
==> windows-server-2016-standard-x64-eval: Overriding defaults Qemu arguments with QemuArgs...
==> windows-server-2016-standard-x64-eval: Waiting 10s for boot...
==> windows-server-2016-standard-x64-eval: Connecting to VM via VNC
==> windows-server-2016-standard-x64-eval: Typing the boot command over VNC...
==> windows-server-2016-standard-x64-eval: Waiting for WinRM to become available...
windows-server-2016-standard-x64-eval: #System.Management.Automation.PSCustomObjectSystem.Object1Preparing modules for first use.0-1-1Completed-1 1Preparing modules for first use.0-1-1Completed-1
==> windows-server-2016-standard-x64-eval: Connected to WinRM!
==> windows-server-2016-standard-x64-eval: Provisioning with Ansible...
==> windows-server-2016-standard-x64-eval: Executing Ansible: ansible-playbook --extra-vars packer_build_name=windows-server-2016-standard-x64-eval packer_builder_type=qemu -i /var/tmp/packer-provisioner-ansible323552097 /var/tmp/packer_windows-server-2016-eval/ansible/win.yml --private-key /var/tmp/ansible-key225720202 --connection packer --extra-vars ansible_shell_type=powershell ansible_shell_executable=None virtio_driver_directory=2k16
windows-server-2016-standard-x64-eval:
windows-server-2016-standard-x64-eval: PLAY [all] *********************************************************************
windows-server-2016-standard-x64-eval:
windows-server-2016-standard-x64-eval: TASK [Gathering Facts] *********************************************************
windows-server-2016-standard-x64-eval: ok: [default]
windows-server-2016-standard-x64-eval:
windows-server-2016-standard-x64-eval: TASK [Enable Remote Desktop] ***************************************************
windows-server-2016-standard-x64-eval: ok: [default]
windows-server-2016-standard-x64-eval:
windows-server-2016-standard-x64-eval: TASK [Allow connections from computers running any version of Remote Desktop (less secure)] ***
windows-server-2016-standard-x64-eval: ok: [default]
windows-server-2016-standard-x64-eval:
windows-server-2016-standard-x64-eval: TASK [Allow RDP traffic] *******************************************************
windows-server-2016-standard-x64-eval: changed: [default]
windows-server-2016-standard-x64-eval:
windows-server-2016-standard-x64-eval: PLAY RECAP *********************************************************************
windows-server-2016-standard-x64-eval: default : ok=4 changed=1 unreachable=0 failed=0
windows-server-2016-standard-x64-eval:
==> windows-server-2016-standard-x64-eval: Restarting Machine
==> windows-server-2016-standard-x64-eval: Waiting for machine to restart...
windows-server-2016-standard-x64-eval: A system shutdown is in progress.(1115)
windows-server-2016-standard-x64-eval: #System.Management.Automation.PSCustomObjectSystem.Object1Preparing modules for first use.0-1-1Completed-1 1Preparing modules for first use.0-1-1Completed-1
==> windows-server-2016-standard-x64-eval: Machine successfully restarted, moving on
==> windows-server-2016-standard-x64-eval: Pausing 1m0s before the next provisioner...
==> windows-server-2016-standard-x64-eval: Uploading scripts/win-common/remove_nic.bat => c:\remove_nic.bat
==> windows-server-2016-standard-x64-eval: Gracefully halting virtual machine...
windows-server-2016-standard-x64-eval:
windows-server-2016-standard-x64-eval: C:\Users\vagrant>echo "*** Downloading devcon64.exe from https://github.com/PlagueHO/devcon-choco-package/raw/master/devcon.portable/devcon64.exe"
windows-server-2016-standard-x64-eval: "*** Downloading devcon64.exe from https://github.com/PlagueHO/devcon-choco-package/raw/master/devcon.portable/devcon64.exe"
windows-server-2016-standard-x64-eval:
windows-server-2016-standard-x64-eval: C:\Users\vagrant>powershell -command "$client = new-object System.Net.WebClient; $client.DownloadFile('https://github.com/PlagueHO/devcon-choco-package/raw/master/devcon.portable/devcon64.exe', 'c:\devcon64.exe')"
windows-server-2016-standard-x64-eval:
windows-server-2016-standard-x64-eval: C:\Users\vagrant>echo "*** Removing the NICs"
windows-server-2016-standard-x64-eval: "*** Removing the NICs"
windows-server-2016-standard-x64-eval:
windows-server-2016-standard-x64-eval: C:\Users\vagrant>for /F "tokens=1 delims=: " %G in ('c:\devcon64.exe findall =net | findstr /c:"Red Hat VirtIO Ethernet Adapter"') do (c:\devcon64.exe remove "@%G" )
==> windows-server-2016-standard-x64-eval: Converting hard drive...
==> windows-server-2016-standard-x64-eval: Running post-processor: vagrant
==> windows-server-2016-standard-x64-eval (vagrant): Creating Vagrant box for 'libvirt' provider
windows-server-2016-standard-x64-eval (vagrant): Copying from artifact: output-windows-server-2016-standard-x64-eval/packer-windows-server-2016-standard-x64-eval
windows-server-2016-standard-x64-eval (vagrant): Using custom Vagrantfile: Vagrantfile-windows.template
windows-server-2016-standard-x64-eval (vagrant): Compressing: Vagrantfile
windows-server-2016-standard-x64-eval (vagrant): Compressing: box.img
windows-server-2016-standard-x64-eval (vagrant): Compressing: metadata.json
Build 'windows-server-2016-standard-x64-eval' finished.

==> Builds finished. The artifacts of successful builds are:
--> windows-server-2016-standard-x64-eval: 'libvirt' provider box: windows-server-2016-standard-x64-eval-libvirt.box
```

Directory structure after build completed:

```text
.
├── ansible
│   └── win.yml
├── http
│   └── windows-server-2016
│   └── Autounattend.xml
├── packer_cache
│   └── 49f719e23c56a779a991c4b4ad1680b8363918cd0bfd9ac6b52697d78a309855.iso
├── scripts
│   └── win-common
│   ├── fixnetwork.ps1
│   └── remove_nic.bat
├── Vagrantfile-windows.template
├── virtio-win.iso
├── windows-server-2016-eval.json
└── windows-server-2016-standard-x64-eval-libvirt.box
```

Necessary files:

- [https://github.com/ruzickap/packer-templates/blob/master/ansible/win.yml](https://github.com/ruzickap/packer-templates/blob/master/ansible/win.yml)
- [https://github.com/ruzickap/packer-templates/blob/master/http/windows-server-2016/Autounattend.xml](https://github.com/ruzickap/packer-templates/blob/master/http/windows-server-2016/Autounattend.xml)
- [https://github.com/ruzickap/packer-templates/blob/master/scripts/win-common/fixnetwork.ps1](https://github.com/ruzickap/packer-templates/blob/master/scripts/win-common/fixnetwork.ps1)
- [https://github.com/ruzickap/packer-templates/blob/master/scripts/win-common/remove_nic.bat](https://github.com/ruzickap/packer-templates/blob/master/scripts/win-common/remove_nic.bat)
- [https://github.com/ruzickap/packer-templates/blob/master/Vagrantfile-windows.template](https://github.com/ruzickap/packer-templates/blob/master/Vagrantfile-windows.template)
- [https://github.com/ruzickap/packer-templates/blob/master/windows-server-2016-eval.json](https://github.com/ruzickap/packer-templates/blob/master/windows-server-2016-eval.json)

This is the real example:

[![asciicast](https://asciinema.org/a/150606.svg)](https://asciinema.org/a/150606)

More complex example can be found here: [https://github.com/ruzickap/packer-templates](https://github.com/ruzickap/packer-templates)

Enjoy ;-)
