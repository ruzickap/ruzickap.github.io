---
title: Android bootanimation
author: Petr Ruzicka
date: 2010-06-17
description: ""
categories: [Android, linux-old.xvx.cz]
tags: [htc-desire, adb]
---

> Not completed...
{: .prompt-info }

I decided to change the boot animation on my HTC Desire.
You can find plenty of them in many places, but I tried to create my own from
a movie.

In this example I'm going to use a movie from
[Big Buck Bunny](https://www.bigbuckbunny.org/) which is licensed under the
[Creative Commons Attribution 3.0](https://creativecommons.org/licenses/by/3.0/)
license. But you can probably use it generally for any movie which can be
played in [mplayer](https://mplayerhq.hu/).

First download the movie:

```bash
wget http://mirror.bigbuckbunny.de/peach/bigbuckbunny_movies/big_buck_bunny_1080p_h264.mov
```

To make it quick you can use this script to create `bootanimation.zip` file. I
commented some parts of the code, so it should be understandable.

```bash
#!/bin/bash

MOVIE_FILE="big_buck_bunny_1080p_h264.mov"
START_AT="0:04:30"
END="2"
START_AT_2="0:06:27"
END_2="2"
SIZE="480x800"
DESC_SIZE="${SIZE/x/ }"

#Create png files from the selected movie part
mplayer -nosound -vo png:z=9:outdir=part0 -ss $START_AT -endpos $END $MOVIE_FILE
mplayer -nosound -vo png:z=9:outdir=part1 -ss $START_AT_2 -endpos $END_2 $MOVIE_FILE

COUNT_PART=1

#Crop every png file to get the right SIZE to fit to your phone
for FILE in part[01]/*.png; do
  echo "*** ($COUNT_PART) $FILE"
  if echo "$FILE" | grep part0; then
    convert "$FILE" -crop 870x1080+510+0 -units PixelsPerCentimeter -type TrueColor -density 37.78x37.78 -depth 8 -resize $SIZE -size $SIZE xc:black +swap -gravity center -composite -verbose "part0/$(printf "%05d.${FILE##*.}" $COUNT_PART)"
    COUNT_PART=$((COUNT_PART + 1))
    #You can add the following frame (but I don't like it) - see imagemagick home page for more details
    # -mattecolor SkyBlue -frame 6x6+2+2
    else
      convert "$FILE" -crop 540x900+1150+150 -units PixelsPerCentimeter -type TrueColor -density 37.78x37.78 -depth 8 -resize $SIZE -size $SIZE xc:black +swap -gravity center -composite -verbose "part1/$(printf "%05d.${FILE##*.}" $COUNT_PART)"
      COUNT_PART=$((COUNT_PART + 1))
  fi
  rm "$FILE"
done

#Write desc file
echo "$DESC_SIZE 30
p 1 0 part0
p 0 0 part1" > desc.txt

#Zip it all to one archive
zip -0 --recurse-paths --move bootanimation.zip part0 part1 desc.txt
```

If you have `bootanimation.zip` you just need to copy it to the phone and
restart it.

```bash
adb push bootanimation.zip /data/local/
adb reboot
```

If you are missing the adb command, please take it from the rooting CD
(described in [Root HTC Desire under Debian][htc-desire]) or from the official
[Android SDK](https://developer.android.com/sdk/index.html).

[htc-desire]: https://linux-old.xvx.cz/2010/05/root-htc-desire-under-debian/

Then you should see something like:

I don't know why the video is so choppy, but maybe it's because the png files
are quite big (if I compare with other available animations), because it has a
lot of colors and high resolution.
