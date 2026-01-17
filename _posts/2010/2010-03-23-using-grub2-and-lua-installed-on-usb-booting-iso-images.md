---
title: Using Grub2 and LUA installed on USB booting ISO images
author: Petr Ruzicka
date: 2010-03-23
description: ""
categories: [Linux, Debian]
tags: [GRUB, Lua, USB, PXE, live-CD]
---

> <https://linux-old.xvx.cz/2010/03/using-grub2-and-lua-installed-on-usb-booting-iso-images-2/>
{: .prompt-info }

I got 16 GB [USB flash](https://en.wikipedia.org/wiki/USB_flash_drive) from
my brother, because he can't see me still using my old 64 MB. He decided
to buy Imation Nano Flash Drive.

Because many of my friends and colleagues are using Windows, I use
[NTFS](https://en.wikipedia.org/wiki/NTFS) on it. Old FAT is not "usable" in
these days, because it can't handle bigger files.

From the first time I used USB disks I always wanted to have a bootable
disk/flash with live CDs - so here are a few notes on how to create a USB flash
drive able to boot stored live CDs:

First you need to compile [grub2](https://www.gnu.org/software/grub/index.html)
yourself, because default grub2 installations in distributions do not
have [LUA](https://en.wikipedia.org/wiki/Lua_%28programming_language%29)
support:

```bash
aptitude install autogen automake bison flex gettext gcc autoconf ruby bzr libfreetype6-dev
```

Debian way compilation and installation:

```bash
aptitude install dpkg-dev fakeroot
apt-get source grub2
apt-get build-dep grub2
dpkg-source -x grub2_1.98-1.dsc

bzr branch http://bzr.savannah.gnu.org/r/grub-extras/lua ./grub2-1.98/debian/grub-extras/lua

cd grub2-1.98
dpkg-buildpackage -rfakeroot -b

cd ..
dpkg -r grub-pc grub-common
dpkg -i ./grub-common_1.98-1_amd64.deb ./grub-pc_1.98-1_amd64.deb
```

Compilation and installation from source code (not necessary if you follow
"Debian steps" above):

```bash
bzr branch http://bzr.savannah.gnu.org/r/grub/trunk/grub
mkdir ./grub/grub-extras
bzr branch http://bzr.savannah.gnu.org/r/grub-extras/lua ./grub/grub-extras/lua
#bzr branch http://bzr.savannah.gnu.org/r/grub-extras/gpxe ./grub/grub-extras/gpxe

cd grub
export GRUB_CONTRIB=./grub-extras/
./autogen.sh
./configure --prefix=/tmp/grub
make
make install
```

Mount USB to some directory (in my case `/mnt/sdb1`) and install grub with Lua
support on it:

```bash
mount /dev/sdb1 /mnt/sdb1
grub-install --root-directory=/mnt/sdb1 /dev/sdb
```

To make grub nicer, I add wallpaper and fonts to it:

```bash
wget --directory-prefix=/tmp/ http://unifoundry.com/unifont-5.1.20080820.pcf.gz
grub-mkfont --output=/mnt/sdb1/boot/grub/unifont.pf2 --range=0x0000-0x0241,0x2190-0x21FF,0x2500-0x259f /tmp/unifont-5.1.20080820.pcf.gz -v -b
wget http://ubuntulife.files.wordpress.com/2007/05/linux.jpg /mnt/sdb1/boot/grub/
```

Last step is creating right configuration and downloading live iso images of
various Linux distributions:

Let's download the ISOs first. It's better to use most actual ones. These are
working fine for me:

```bash
mkdir -v /mnt/sdb1/isos
wget -c --directory-prefix=/mnt/sdb1/isos \
http://ftp.heanet.ie/pub/linuxmint.com/testing/LinuxMint-8-x64-RC1.iso \
http://gd.tuwien.ac.at/opsys/linux/grml/grml64_2009.10.iso \
http://ftp.cc.uoc.gr/mirrors/linux/slax/SLAX-6.x/slax-6.1.2.iso \
http://downloads.sourceforge.net/project/systemrescuecd/sysresccd-x86/1.5.0/systemrescuecd-x86-1.5.0.iso \
http://releases.ubuntu.com/karmic/ubuntu-9.10-desktop-amd64.iso \
http://xpud.googlecode.com/files/xpud-0.9.2.iso
```

The following code is taken from [Ubuntu Forums](https://ubuntuforums.org)
where I added more live CDs. I also changed the main `grub.cfg` a little bit and
use 64 live CDs `amd64`.

Save following text as 3 files:

- `/mnt/sdb1/boot/grub/grub.cfg`:

  ```bash
  insmod vbeinfo
  insmod font

  if loadfont /boot/grub/unifont.pf2 ; then
    set gfxmode="1024x768x32,800x600x32,640x480x32,1024x768,800x600,640x480"
  #  set gfxpayload=keep
    insmod gfxterm
  #  insmod vbe
    if terminal_output gfxterm; then true ; else
       terminal gfxterm
    fi
  fi

  insmod jpeg
  if background_image /boot/grub/linux.jpg ; then
    set menu_color_normal=black/black
    set color_highlight=red/blue
  else
    set menu_color_normal=cyan/blue
    set menu_color_highlight=white/blue
  fi

  set default=0
  set timeout=10

  # Uncomment for a different ISO files search path
  #set isofolder="/boot/isos"
  #export isofolder

  # Uncomment for a different live system language
  #set isolangcode="us"
  #export isolangcode

  source /boot/grub/listisos.lua
  ```

- `/mnt/sdb1/boot/grub/bootiso.lua`:

  ```lua
  #!lua

  -- Detects the live system type and boots it
  function boot_iso (isofile, langcode)
    -- grml
    if (dir_exist ("(loop)/boot/grml64")) then
      boot_linux (
        "(loop)/boot/grml64/linux26",
        "(loop)/boot/grml64/initrd.gz",
        "findiso=" .. isofile .. " apm=power-off quiet boot=live nomce"
      )
    -- Parted Magic
    elseif (dir_exist ("(loop)/pmagic")) then
      boot_linux (
        "(loop)/pmagic/bzImage",
        "(loop)/pmagic/initramfs",
        "iso_filename=" .. isofile ..
          " edd=off noapic load_ramdisk=1 prompt_ramdisk=0 rw" ..
          " sleep=10 loglevel=0 keymap=" .. langcode
      )
    -- Sidux
    elseif (dir_exist ("(loop)/sidux")) then
      boot_linux (
        find_file ("(loop)/boot", "vmlinuz%-.*%-sidux%-.*"),
        find_file ("(loop)/boot", "initrd%.img%-.*%-sidux%-.*"),
        "fromiso=" .. isofile .. " boot=fll quiet"
      )
    -- Slax
    elseif (dir_exist ("(loop)/slax")) then
      boot_linux (
        "(loop)/boot/vmlinuz",
        "(loop)/boot/initrd.gz",
        "from=" .. isofile .. " ramdisk_size=6666 root=/dev/ram0 rw"
      )
    -- SystemRescueCd
    elseif (grub.file_exist ("(loop)/isolinux/rescue64")) then
      boot_linux (
        "(loop)/isolinux/rescue64",
        "(loop)/isolinux/initram.igz",
        "isoloop=" .. isofile .. " docache rootpass=xxxx setkmap=" .. langcode
      )
    -- Tinycore
    elseif (grub.file_exist ("(loop)/boot/tinycore.gz")) then
      boot_linux (
        "(loop)/boot/bzImage",
        "(loop)/boot/tinycore.gz"
      )
    -- Ubuntu and Casper based Distros
    elseif (dir_exist ("(loop)/casper")) then
      boot_linux (
        "(loop)/casper/vmlinuz",
        find_file ("(loop)/casper", "initrd%..z"),
        "boot=casper iso-scan/filename=" .. isofile ..
          " quiet splash noprompt" ..
          " keyb=" .. langcode ..
          " debian-installer/language=" .. langcode ..
          " console-setup/layoutcode?=" .. langcode ..
          " --"
      )
    -- Xpud
    elseif (grub.file_exist ("(loop)/boot/xpud")) then
      boot_linux (
        "(loop)/boot/xpud",
        "(loop)/opt/media"
      )
    else
      print_error ("Unsupported ISO type")
    end
  end

  -- Help function to show an error
  function print_error (msg)
    print ("Error: " .. msg)
    grub.run ("read")
  end

  -- Help function to search for a file
  function find_file (folder, match)
    local filename

    local function enum_file (name)
      if (filename == nil) then
        filename = string.match (name, match)
      end
    end

    grub.enum_file (enum_file, folder)

    if (filename) then
      return folder .. "/" .. filename
    else
      return nil
    end
  end

  -- Help function to check if a directory exist
  function dir_exist (dir)
    return (grub.run("test -d '" .. dir .. "'") == 0)
  end

  -- Boots a Linux live system
  function boot_linux (linux, initrd, params)
    if (linux and grub.file_exist (linux)) then
      if (initrd and grub.file_exist (initrd)) then
        if (params) then
          grub.run ("linux " .. linux .. " " .. params)
        else
          grub.run ("linux " .. linux)
        end
        grub.run ("initrd " .. initrd)
      else
        print_error ("Booting Linux failed: cannot find initrd file '" .. initrd .. "'")
      end
    else
      print_error ("Booting Linux failed: cannot find linux file '" .. initrd .. "'")
    end
  end

  -- Mounts the iso file
  function mount_iso (isofile)
    local result = false

    if (isofile == nil) then
      print_error ("variable 'isofile' is undefined")
    elseif (not grub.file_exist (isofile)) then
      print_error ("Cannot find isofile '" .. isofile .. "'")
    else
      local err_no, err_msg = grub.run ("loopback loop " .. isofile)
      if (err_no ~= 0) then
        print_error ("Cannot load ISO: " .. err_msg)
      else
        result = true
      end
    end

    return result
  end

  -- Getting the environment parameters
  isofile = grub.getenv ("isofile")
  langcode = grub.getenv ("isolangcode")
  if (langcode == nil) then
    langcode = "us"
  end

  -- Mounting and booting the live system
  if (mount_iso (isofile)) then
    boot_iso (isofile, langcode)
  end
  ```

- `/mnt/sdb1/boot/grub/listisos.lua`:

  ```lua
  #!lua

  isofolder = grub.getenv ("isofolder")
  if (isofolder == nil) then
    isofolder = "/isos"
  end

  function enum_file (name)
    local title = string.match (name, "(.*)%.[iI][sS][oO]")

    if (title) then
      local source = "set isofile=" .. isofolder .. "/" .. name ..
        "\nsource /boot/grub/bootiso.lua"

      grub.add_menu (source, title)
    end
  end

  grub.enum_file (enum_file, isofolder)
  ```

**UPDATE**: In the new grub versions I had to modify following lines
(from `source` -> `lua` and one module name `vbeinfo` -> `vbe`) otherwise it was
not running correctly. Please look at these lines and change it in the scripts
above:

```lua
insmod vbe

lua /boot/grub/listisos.lua

      "\nlua /boot/grub/bootiso.lua"
```

After unmounting your USB flash should be bootable and you should get menu
similar to this one:

![GRUB2 USB Boot Menu](/assets/img/posts/2010/2010-03-23-using-grub2-and-lua-installed-on-usb-booting-iso-images/grub_usb.avif)

Enjoy :-)
