---
title: Trim margins from PDF document
author: Petr Ruzicka
date: 2009-06-02
description: Use pdfcrop to trim large margins from PDF documents
categories: [Linux, linux-old.xvx.cz]
tags: [bash]
---

> <https://linux-old.xvx.cz/2009/06/trim-margins-from-pdf-document/>
{: .prompt-info }

It happened to me once that I wanted to trim margins from a PDF document.

It was a manual for the Panasonic G1 camera.

You can see huge margins there, because it was officially written for A5 paper
and they created a manual for A4.

See the picture:

![One page from Czech Panasonic DMC-G1 manual](/assets/img/posts/2009/2009-06-02-trim-margins-from-pdf-document/dmc-g1.avif)

I used [pdfcrop](https://www.ctan.org/tex-archive/support/pdfcrop/) script from
Heiko Oberdiek, which can easily trim margins:

```bash
pdfcrop.pl --margins 10 panasonic_g1.pdf panasonic_g1-2.pdf
```

Here is the result:

![Trimmed page from Czech Panasonic DMC-G1 manual](/assets/img/posts/2009/2009-06-02-trim-margins-from-pdf-document/dmc-g1_2.avif)

I hope this can be useful for somebody who needs this...

The KDE PDF viewer Okular has the function "Trim Margins", which works very
well, but you cannot save the PDF...
