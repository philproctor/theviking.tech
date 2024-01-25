---
title: "Actual Portable Scripting with Nix"
date: 2024-01-25T09:00:00-04:00
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
to understand configuration language. Fortunately, for our purposes here, these drawbacks will be mitigated by setting up a relatively
unchanging scaffolded environment.

## Bowls of Nix Flakes

[Nix Flakes](https://nixos.wiki/wiki/Flakes) is the system we use to provide both package locking and execution environment management.
I have created [this demo here](https://github.com/philproctor/nix-script-runner-demo) to show a solid setup for using flakes, so let's
break down the demo and see how it works!

{{< asciinema name="nix1" rows=16 cols=140 >}}

From the above demo you can see that when you one of the scripts in the demo are run for the first time, all of the dependendent utilities
for the script are automatically downloaded and made available to the script environment! This means that any utilities that you need in
your script, such as `jq`, `kubectl`, or just about anything else are automatically pulled without you as a user needing to think about it
at all!

## Our Customized Scaffold

The scaffolding is primarily handled through the `flake.nix` file, but additionally includes an easy-of-use wrapper for running scripts.

### The ./run Wrapper

The [./run wrapper](https://github.com/philproctor/nix-script-runner-demo/blob/main/run) is used to make executing individual scripts easier,
especially for users of your project who are not familiar with the (quite quirky) nix command line. Additionally, the wrapper includes some
basic messaging if the user doesn't have the nix tools installed or forgets to specify which script to execute. As most of this wrapper is
self-explanatory, let's move on to the guts of our scaffolding: `flake.nix`

### Diving in to our Customized Nix Flake

One of the biggest concerns I have had with using the Nix tooling in projects with a wider and mixed skillset is that we don't want to require
everyone on the team or users of the project to need to learn and understand **Yet Another Domain Specific Language™** just to solve package
management requirements around our primary scripts. So [here's out attempt to gain these advantages without requiring users to fully understand
Nix](https://github.com/philproctor/nix-script-runner-demo/blob/main/flake.nix).

The basic structure of using `inputs = {...` and `outputs = {...` is defined by the [Flake schema](https://nixos.wiki/wiki/Flakes#Flake_schema).
You may notice that we are using `nixpkgs-unstable` as one of our inputs and that might be a tad alarming to some to see that, however it's worth
remembering that our automatically generated `flake.lock` will ensure that whatever versions of packages we use do not change without us
intentionally changing them. If the use of the unstable channel is concerning, however, it can be locked to one of the stable releases such as
`23.11` at the time of this writing.

Next up, we define our dependencies:

```bash
scriptDeps = with pkgs; [
    nixFormatter
    jq
    git
    curl
    kubectl
];
```

Every one of these packages will be installed to the environment that our scripts are executed in. For any utilities you want
to add, all you have to do is search for them [in the NixOS package search](https://search.nixos.org/packages) and add them to the list! For
example, we added `kubectl` to the list from [this search](https://search.nixos.org/packages?channel=unstable&from=0&size=50&sort=relevance&type=packages&query=kubectl)

Next, we want to make it so that the addition or removal of scripts can be done without needing to touch our Nix code at all. The way we accomplish
this is by having our flake scan the `scripts/` directory for files that have some predetermined extensions. This means that if someone wants to
add a new script to our project, all they have to do is add it to the `scripts/` directory with one of the extensions that we specify; no nix code
required!

We also want to allow multiple "types" of scripts, automatically determined by extension, so that we can change script headers, footers, or even
dependencies based on the extension of the script. While the demo only includes BASH scripts, this could also allow for running any other types of
scripts such as python, go, or so on. In our demo, we specify two extensions `.std.sh` and `.tf.sh` like so:

```bash
# headers here, defined outside the list so they can refer to each other
stdShHeader = ''
    #!${pkgs.stdenv.shell}
    set -Eeou pipefail
    export PATH="$PATH:${scriptEnv}/bin"
'';
tfShHeader = ''
    ${stdShHeader}
    echo 'Running the extra tasks for .tf.sh'
'';

# Define metadata for each file suffix and the headers/exec command to attach to them
scriptSuffixes = [
    {
    suffix = ".std.sh";
    header = stdShHeader;
    command = "exec";
    }
    {
    suffix = ".tf.sh";
    header = tfShHeader;
    command = "exec";
    }
];
```

In our usage here, we're defining `stdShHeader` and `tfShHeader` outside of our list of suffixes to keep it easy to refer to other headers, but
these could just as easily be defined inline with our list.

Finally, the real workhorse of our customized flake. This is where we do the actual walking of the `scripts/` directory using the metadata defined
in the list above:

```bash
scriptMappings = builtins.map
        # for each script suffix we...
        (typeAttrs:
        let
            # Find all scripts in the directory with our expected suffix
            scriptsFound = builtins.filter (name: lib.hasSuffix typeAttrs.suffix name) scriptDirScripts;
            # Map those found scripts to command names such that `format.std.sh` becomes `format`
            scriptNames = builtins.map (name: builtins.replaceStrings [ typeAttrs.suffix ] [ "" ] name) scriptsFound;
            # Create a list of maps where the command is set to "name" and the path to the script is set to "value", e.g. [{"name":"format","value":"./scripts/format.std.sh", ...}]
            scriptAttrLists = builtins.map (name: { name = name; value = scriptDir + "/${name}${typeAttrs.suffix}"; }) scriptNames;
            # Convert that list of maps into a single mapping where command name is the key, path is the value. e.g. {"format":"./scripts/format.std.sh", ...}
            scriptAttrs = builtins.listToAttrs scriptAttrLists;
            # Finally, instead of JUST the path, add the full formatting of the wrapper script (including the header and exec command) to the values
            # {"format": "<all contents of wrapper script>", ...}
            scriptContents = builtins.mapAttrs
            (name: value: ''
                ${typeAttrs.header}
                ${typeAttrs.command} ${value} "$@"
            '')
            scriptAttrs;
        in
        scriptContents)
    scriptSuffixes;
```

We'll let the comments in the above snippets do most of the talking, but basically we are creating a script mapping from each of the scripts found
and adding the script headers and exec command. This mapping effectively creates a "wrapper" script for each one of the scripts found that might look
something like this for the command `./run format`:

```bash
#!/usr/bin/env bash
set -Eeou pipefail
export PATH="$PATH:/nix/store/generated-env-dir/bin"
exec ./scripts/format.std.sh "$@"
```

### The Help Command

We also want to ensure that our code is as self-documenting as possible while also keeping documentation simple. While this isn't a replacement for
complete documentation by other means, maintaining quick help text can be made semi-automatic. To do this, we can just add another script file to our
project called `help.std.sh`. You can
[see the full contents of the demo help script here](https://github.com/philproctor/nix-script-runner-demo/blob/main/scripts/help.std.sh).

In a nutshell what we do though is this:

- Scan the `scripts/` directory for files that end in the extensions that we care about (`.std.sh` and `.tf.sh`)
- For each script that we find, use `grep` to find the first line of code that starts with `# HELPTEXT:`
- Output each script command along with the HELP output in a human readable format.

The result looks like this:
```bash
$ ./run help
Usage: ./run <command> [args...]

Standard commands:
  format                        Format flake.nix
  help                          Display this help output
  update-packages               Update the flake.lock with the latest version of all dependencies

Terraform commands:
  test                          Demo for files with a .tf.sh extension instead

note: any arguments passed after <command> are passed directly to the script that handles that command.
```

## Final Results

What we're left with after doing this project is a structure that looks like this:

- 📂 `scripts/`
  - 📄 `help.std.sh`
  - 📄 `format.std.sh`
  - 📄 `test.tf.sh`
  - 📄 `update-packages.std.sh`
- 📄 `flake.nix`
- 📄 `flake.lock`
- 📄 `run`

The maintenance once the boilerplate is done is simple:

- Any scripts that we want to add to this project can then simply be added to the `scripts/` folder with one of our extensions and it will be autodetected as a new `run` command. Remember that scripts need to be in git `git add` and need to be executable `chmod +x`.
- Any new dependencies can be added to `scriptDeps` inside of `flake.nix`
- Updating the dependency lock can be done with `./run update-packages`
- New types of scripts, such as python scripts, can be supported by amending `scriptSuffixes` in `flake.nix` and updating dependencies
- New users of the project do not need to install **any** dependencies except for Nix itself. Our `run` script will dump a message telling them to install Nix if it's missing.
