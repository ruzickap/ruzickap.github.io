---
title: digiKam thumbnails and Albums with photos stored on remote shares
author: Petr Ruzicka
date: 2009-03-22
categories: [Linux, Desktop]
tags: [bash, digiKam, KDE]
---

My photo collection is stored on the server and accessed by cifs protocol to my
notebooks. I'm using [digiKam](https://www.digikam.org/) to browse my collection
in KDE.

This software is storing all thumbnails in `~/.thumbnails/` according to the
[thumbnail spec](https://specifications.freedesktop.org/thumbnail-spec/thumbnail-spec-latest.html)
and creates a [sqlite](https://www.sqlite.org/) database where it stores all
information about photos.

- The advantage is, that these thumbnails can be also used by other KDE
  viewers (like [Gwenview](https://apps.kde.org/gwenview/)).
- The disadvantage can be that other viewers can generate new thumbnails
  which are no longer useful and the size of that directory can grow...

I decided to write a script which can delete all useless thumbnails and keep
only the ones used by digiKam. The reason is simple - I don't want to remove all
thumbnails and regenerate them again only from digiKam, because I have more than
35k photos so it takes a long time...

Here is my digiKam collection configuration:

![digiKam Configuration](/assets/img/posts/2009/2009-03-22-digikam-thumbnails-and-albums-with-photos-stored-on-remote-shares/digikam-configure.avif)

This script deletes all thumbnails of the photos in `$HOME/.thumbnails/large/`

 which are **not** on network shares :

(It preserves all the thumbnails of photos stored on network share, which take
ages to create because of network or which are not changing, and delete all
locally ones)

[thumbnails_delete.pl](https://websvn.xvx.cz/wsvn/projects/trunk/scripts/thumbnails_delete/thumbnails_delete.pl)

Maybe you can find it helpful...
