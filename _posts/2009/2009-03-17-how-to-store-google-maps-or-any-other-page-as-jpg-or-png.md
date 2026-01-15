---
title: How to store Google Maps (or any other page) as jpg or png
author: Petr Ruzicka
date: 2009-03-17
categories: [Linux, Desktop]
tags: [KDE, Firefox]
---

I'm using my old Palm TX to navigate during my travels. I don't have GPS, but I
usually get some maps from the web, store them as jpg and view on Palm as a
picture.

I had problems to get big maps from Google to jpg, because all screen snapshot
programs can only get actual "screen" (usually just 1440x900).

My palm and other devices can handle much bigger images and it's possible to
scroll them. My laptop screen resolution was quite limiting... :-(

---

I found solution in KDE:

1. Install Firefox add-on called Abduction! It will allow you to save pages or
   part of the page as image (File -> Save Page As Image...)
2. Run Firefox and chose your place in the map.
3. Press ALT + F3 -> Advanced -> Special Windows Settings...

<!-- rumdl-disable MD013 -->
[![Advanced Windows Settings - KDE](/assets/img/posts/2009/2009-03-17-how-to-store-google-maps-or-any-other-page-as-jpg-or-png/advanced_settings.avif)](/assets/img/posts/2009/2009-03-17-how-to-store-google-maps-or-any-other-page-as-jpg-or-png/advanced_settings.avif)
<!-- rumdl-enable MD013 -->
*Advanced Windows Settings - KDE*

1. Select Geometry tab and modify "Size" parameters:

<!-- rumdl-disable MD013 -->
[![Edit Window Specific Settings Kwin](/assets/img/posts/2009/2009-03-17-how-to-store-google-maps-or-any-other-page-as-jpg-or-png/edit_window-specific_settings-kwin.avif)](/assets/img/posts/2009/2009-03-17-how-to-store-google-maps-or-any-other-page-as-jpg-or-png/edit_window-specific_settings-kwin.avif)
<!-- rumdl-enable MD013 -->
*Edit Window Specific Settings Kwin*

Then your Firefox should be much bigger (above screen borders) and you should be
able to save "one big" page as image...
