---
title: CKA - Kubernetes Certified Administrator exam tips
author: Petr Ruzicka
date: 2018-04-19
description: CKA - Kubernetes Certified Administrator exam tips
categories: [Kubernetes]
tags: [kubernetes, cka, kubectl]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2018/04/cka-kubernetes-certified-administrator.html)
{: .prompt-info }

I passed the Kubernetes Certified Administrator exam recently and I would like
to share some tips.

I was looking for some details about the exam before, but most of the articles I
found are quite old:

- [https://medium.com/@walidshaari/kubernetes-certified-administrator-cka-43a25ca4c61c](https://medium.com/@walidshaari/kubernetes-certified-administrator-cka-43a25ca4c61c)
- [https://github.com/walidshaari/Kubernetes-Certified-Administrator](https://github.com/walidshaari/Kubernetes-Certified-Administrator)
- [https://web.archive.org/web/20180321024730/http://madorn.com/certified-kubernetes-administrator-exam.html](https://web.archive.org/web/20180321024730/http://madorn.com/certified-kubernetes-administrator-exam.html)
- [https://blog.heptio.com/how-heptio-engineers-ace-the-certified-kubernetes-administrator-exam-93d20af32557](https://blog.heptio.com/how-heptio-engineers-ace-the-certified-kubernetes-administrator-exam-93d20af32557)

![CKA Certified Kubernetes Administrator logo](https://raw.githubusercontent.com/cncf/artwork/c33a8386bce4eabc36e1d4972e0996db4630037b/other/cka/color/kubernetes-cka-color.svg){:width="300"}

So I decided to write some more fresh stuff from the April 2018.

- You will have access to one terminal window where you are switching between
  Kubernetes clusters using "kubectl config use-context ". (Every exercise
  starts with a command showing you which cluster to use.) Here is how it looks
  (picture is taken from [web.archive.org](https://web.archive.org/web/20180321024730/http://madorn.com/certified-kubernetes-administrator-exam.html))

  ![CKA exam terminal interface screenshot](https://s3.amazonaws.com/madorn.com/images/cka-exam.jpeg)

- When you are doing some cluster troubleshooting it may be useful to know
  "**[screen](https://www.gnu.org/software/screen/)**" command and [how to
  work](https://www.howtoforge.com/linux_screen) with it. It's handy when you
  need to quickly switch between cluster node sessions, because you have only
  one terminal window.

- Absolute must is to enable bash completion on the "master station" where you
  will be running all the `kubectl` commands. This handy autocomplete will speed
  up your work significantly - you can enable it by running:
  `<(kubectl completion bash)` ([https://kubernetes.io/docs/reference/kubectl/cheatsheet/](https://kubernetes.io/docs/reference/kubectl/cheatsheet/))
  Examples can be found here: [https://blog.heptio.com/kubectl-shell-autocomplete-heptioprotip-48dd023e0bf3](https://blog.heptio.com/kubectl-shell-autocomplete-heptioprotip-48dd023e0bf3)

- Web console used on the exam has some limitations so be prepared that it's not
  as easy to manage as your favorite terminal. See the Exam Handbook how to use
  **Copy & Paste** and do not use the bash shortcut "Ctrl + W" for deleting word
  if you are used to.

- During the exam I marked some questions which I would like to look at before
  the exam ends. Actually I **didn't have time** to do it - so do not expect
  that you will have much time left to return to some questions...

- If you are completely lost with some hard questions - it's better to skip them
  or just give them **limited amount of time**.

- There is a **notepad** in your browser available during the exam - so use it
  for your notes.

- Be familiar with structure of **[kubernetes.io](https://kubernetes.io)** and
  how to search there. This is the only page which can be opened in the second
  browser tab and you are allowed to use it.

- You should practice your Kubernetes knowledge on multinode cluster.
  [minikube](https://github.com/kubernetes/minikube) is very handy to spin up
  the Kubernetes easily, but it has only single node. All clusters in CKA exam
  are multinode clusters and you should know how to work with them.
  Feel free to look at this page how to quickly install the **multinode
  Kubernetes cluster** (using `kubeadm`):
  "[Cheapest Amazon EKS]({% post_url /2018/2018-04-18-create-kubernetes-multinode-cluster-using-multiple-vms %})"

Other CKA exam details can be found on many blogs / pages / handbooks and I do
not want to cover them here. I just point to the most important ones...

Enjoy ;-)
