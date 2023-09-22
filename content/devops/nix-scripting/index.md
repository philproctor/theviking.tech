---
title: "Actual Portable Scripting with Nix"
date: 2023-09-21T23:18:30-04:00
draft: false
toc: false
tags: [devops, scripting, nix, posts]
---

Scripting is among the most common tasks that we have in the world of devops. Whether we are writing shell scripts,
python, or whatever language we've found ourselves using, we will next need to make sure that those same scripts are
usable by other people, continuous integration, or any other automation.

So what next? Write up a set of instructions for what utilities need to be installed? Create a `Dockerfile` with all
of the `apt-get` installs? Do instructions for people, Dockerfile for CI? Containerize everything and map host paths
to the host machines config files and whatnot?

Every one of these solutions comes with their own compromises. Additionally, these solutions are very likely to break
over time when [packages update with breaking changes](https://learn.microsoft.com/en-us/cli/azure/upcoming-breaking-changes),
packages get removed, or any number of other scenarios. This leads to having to update instructions, Dockerfiles, scripts,
and so forth at what is likely a very inconvenient time and after you've already forgotten how those scripts work!

Well, we don't have to deal with that... at least a little less.

## Introducing Nix

We are likely all familiar at this point with the package management systems that come with various languages.

- Nuget for C#
- NPM for node.js
- pip/venv for Python
- The list here could get very long...

If you think about a generic package management solution for scripting, you are probably thinking about `apt-get` or `yum`.
These, however, have several distinct disadvantages over the solutions listed above:

- These utilities are tied to the OS and thus vary significantly between machines (redhat, debian, arch, etc.)
- It is unlikely that the versions of the utilities two people end of using are the same (my version of bash is 5.2.15, what's yours?)
- They don't provide any package locking type solutions
- Each package manager doesn't even have the same library of utilities available

Nix fixes all of these problems. Additionally, it fixes it regardless of the OS the user is using and allows you to fully define
**everything** about the execution environment of the scripts you are running. Nix is powerful enough that it can even be used to replace
the package management systems above, though usually the preferred route is to simply tie into those systems.

Too good to be true? Well, no system is perfect. There are significant drawbacks to Nix, including poor documentation and a difficult
to understand configuration language. Fortunately, for our purposes here, these drawbacks will be mitigated.

## Bowls of Nix Flakes

[Nix Flakes](https://nixos.wiki/wiki/Flakes) is the system we use to provide both package locking and execution environment management.
I have created [this demo here](https://github.com/philproctor/nix-script-runner-demo) to show a solid setup for using flakes, so let's
break down the demo and see how it works!

{{< asciinema name="nix1" rows=5 >}}
