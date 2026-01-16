---
title: HD Trailers downloaded by wget
author: Petr Ruzicka
date: 2009-03-05
categories: [Linux, Scripting]
tags: [bash, wget]
---

> <https://linux-old.xvx.cz/2009/03/hd-trailers-downloaded-by-wget/>
{: .prompt-info }

I found nice page [hd-trailers.net](https://www.hd-trailers.net/) accessing
HD trailers from Yahoo or [Apple](https://www.apple.com/trailers/) through
downloadable [mov](https://en.wikipedia.org/wiki/.mov) files. It's quite
useful to have mov files instead of using flash player especially if you
have slower Internet connection.

Here is short [wget](https://www.gnu.org/software/wget/) command which download
mov files from Apple site into directories:

```bash
#!/bin/bash

#480, 720, 1080
RESOLUTION=480

wget --recursive --level=2  --accept *${RESOLUTION}p.mov \
--span-hosts --domains=movies.apple.com,www.hd-trailers.net \
--no-host-directories --cut-dirs=2 --exclude-directories=/blog \
http://www.hd-trailers.net/
```

Enjoy ;-)
