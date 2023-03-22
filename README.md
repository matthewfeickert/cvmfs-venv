# cvmfs-venv

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.7751033.svg)](https://doi.org/10.5281/zenodo.7751033)

Simple command line utility for getting a Python virtual environment to work with CVMFS [LCG views][LCG_info]. This is done by adding additional hooks to the Python virtual environment's `bin/activate` script.

[LCG_info]: https://lcginfo.cern.ch/

## Install

Either clone the repo to your directory or simply download the relevant files and place on `PATH`

```console
$ mkdir -p ~/.local/bin
$ export PATH=~/.local/bin:"${PATH}"  # If ~/.local/bin not on PATH already
$ curl -sL https://raw.githubusercontent.com/matthewfeickert/cvmfs-venv/main/cvmfs-venv.sh -o ~/.local/bin/cvmfs-venv
$ chmod +x ~/.local/bin/cvmfs-venv
```

## Use

Source the script to create a Python 3 virtual environment that can coexist with a CVMFS LCG view. The default name is `venv`.

```console
$ cvmfs-venv --help
Usage: cvmfs-venv [-s|--setup] [--no-system-site-packages] [--no-update] <virtual environment name>

Options:
 -h --help      Print this help message
 -s --setup     String of setup options to be parsed
 --no-system-site-packages
                The venv module '--system-site-packages' option is used by
                default. While it is not recommended, this behavior can be
                disabled through use of this flag.
 --no-update    After venv creation don't update pip, setuptools, and wheel
                to the latest releases. Use of this option is not recommended,
                but is faster.

Note: cvmfs-venv extends the Python venv module and so requires Python 3.3+.

Examples:

    * Create a Python 3 virtual environment named 'lcg-example' with the Python
    runtime provided by LCG view 102 on CentOS7.

        setupATLAS -3
        lsetup 'views LCG_102 x86_64-centos7-gcc11-opt'
        cvmfs-venv lcg-example
        . lcg-example/bin/activate

    * Create a Python 3 virtual environment named 'atlas-ab-example' with the
    Python runtime provided by ATLAS AnalysisBase release v22.2.113.

        setupATLAS -3
        asetup AnalysisBase,22.2.113
        cvmfs-venv atlas-ab-example
        . atlas-ab-example/bin/activate

    * Create a Python 3 virtual environment named 'venv' with whatever Python
    runtime "\$(command -v python3)" evaluates to.

        cvmfs-venv
        . venv/bin/activate

    * Setup LCG view 102 on CentOS7 and create a Python virtual environment
    named 'lcg-example' using the Python 3.9 runtime it provides.

        . cvmfs-venv --setup "lsetup 'views LCG_102 x86_64-centos7-gcc11-opt'" lcg-example

    * Setup ATLAS AnalysisBase release v22.2.113 and create a Python virtual
    environment named 'atlas-ab-example' using the Python 3.9 runtime it
    provides.

        . cvmfs-venv --setup 'asetup AnalysisBase,22.2.113' atlas-ab-example
```

### Example: Virtual environment with LCG view

```console
$ ssh lxplus
[feickert@lxplus732 ~]$ mkdir -p ~/.local/bin
[feickert@lxplus732 ~]$ export PATH=~/.local/bin:"${PATH}"
[feickert@lxplus732 ~]$ curl -sL https://raw.githubusercontent.com/matthewfeickert/cvmfs-venv/main/cvmfs-venv.sh -o ~/.local/bin/cvmfs-venv
[feickert@lxplus732 ~]$ chmod +x ~/.local/bin/cvmfs-venv
[feickert@lxplus732 ~]$ setupATLAS -3 --quiet
[feickert@lxplus732 ~]$ lsetup 'views LCG_102 x86_64-centos7-gcc11-opt'
************************************************************************
Requested:  views ...
 Setting up views LCG_102:x86_64-centos7-gcc11-opt ...
>>>>>>>>>>>>>>>>>>>>>>>>> Information for user <<<<<<<<<<<<<<<<<<<<<<<<<
************************************************************************
[feickert@lxplus732 ~]$ cvmfs-venv lcg-example
# Creating new Python virtual environment 'lcg-example'
[feickert@lxplus732 ~]$ . lcg-example/bin/activate
(lcg-example) [feickert@lxplus732 ~]$ python -m pip show lhapdf  # Still have full LCG view
Name: LHAPDF
Version: 6.5.1
Summary: The LHAPDF parton density evaluation library
Home-page: https://lhapdf.hepforge.org/
Author: LHAPDF Collaboration
Author-email: lhapdf-dev@cern.ch
License: GPLv3
Location: /cvmfs/sft.cern.ch/lcg/views/LCG_102/x86_64-centos7-gcc11-opt/lib/python3.9/site-packages
Requires:
Required-by:
(lcg-example) [feickert@lxplus732 ~]$ python -m pip install --upgrade awkward  # This will show a false ERROR given CVFMS is in PYTHONPATH
(lcg-example) [feickert@lxplus732 ~]$ python
Python 3.9.12 (main, Jun  7 2022, 16:09:12)
[GCC 11.2.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import ROOT
>>> import XRootD
>>> import awkward
>>> exit()
(lcg-example) [feickert@lxplus732 ~]$ python -m pip show awkward  # Get version installed in venv
Name: awkward
Version: 2.1.1
Summary: Manipulate JSON-like data with NumPy-like idioms.
Home-page:
Author:
Author-email: Jim Pivarski <pivarski@princeton.edu>
License: BSD-3-Clause
Location: /afs/cern.ch/user/f/feickert/lcg-example/lib/python3.9/site-packages
Requires: awkward-cpp, numpy, packaging, typing-extensions
Required-by: coffea
(lcg-example) [feickert@lxplus732 ~]$ python -m pip list --local  # View of virtual environment controlled packages
Package           Version
----------------- -------
awkward           2.1.1
awkward-cpp       12
pip               23.0.1
setuptools        67.6.0
typing_extensions 4.5.0
wheel             0.40.0
(lcg-example) [feickert@lxplus732 ~]$ deactivate  # Resets PYTHONPATH given added hooks
[feickert@lxplus732 ~]$ python -m pip show awkward  # Get CVMFS's old version
Name: awkward
Version: 1.7.0
Summary: Manipulate JSON-like data with NumPy-like idioms.
Home-page: https://github.com/scikit-hep/awkward-1.0
Author: Jim Pivarski
Author-email: pivarski@princeton.edu
License: BSD-3-Clause
Location: /cvmfs/sft.cern.ch/lcg/views/LCG_102/x86_64-centos7-gcc11-opt/lib/python3.9/site-packages
Requires: numpy, setuptools
Required-by: coffea
```

## Dependencies

`cvmfs-venv` has no dependencies beyond the ones it aims to extend: A Linux operating system that has CVMFS installed on it with a Python 3.3+ runtime with a functioning [`venv` module][venv docs].

A full listing of all programs used outside of Bash shell builtins are:
* `cat`
* `ed`
* `find`
* `readlink`
* `sed`
* Python 3.3+ with `pip`

## Why is this needed?

When an LCG view or an ATLAS computing environment that uses software from CVFMS is setup, it manipulates and alters the [`PYTHONPATH` environment variable][PYTHONPATH docs].
By placing the contents of all the installed software of an LCG view or ATLAS release onto `PYTHONPATH` for the rest of the shell session, the protections and isolation of a Python virtual environment are broken.
It is not possible to fix this in a reliable and robust way that will not break the access of other software in the LCG view or ATLAS environment dependent on the Python packages in them.
The best that can be done is to control the directory tree at the **head** of `PYTHONPATH` in a stable manner that allows for most of the benefits of a Python virtual environment (control of install and versions of packages, isolation of directory tree).

While [`lcgenv`][lcgenv] allows for package specific environment building, it still lacks the control to specify arbitrary versions of Python packages and will load additional libraries beyond what is strictly required by the target package dependency requirements.
That being said, if you are able to use an LCG view or `lcgenv` without any additional setup, you may not have need of specifying a Python virtual environment.

While Python's [`venv` module][venv docs] does have the `--system-site-packages` option to

> Give the virtual environment access to the system site-packages dir.

this unfortunately isn't _quite_ enough.
It does allow for isolation to work, but the manipulation of `PYTHONPATH` makes it so that while packages can be _installed_ properly in the local virtual environment and will show up with `python -m pip list` if there is another version of that package provided by the already setup environment that package version's location on `PYTHONPATH` will take precedence.
Using `--system-site-packages` without `cvmfs-venv` is arguably even worse as it provides confusing differences in information between what `pip` has purported to install in the user's virtual environment and the user `pip list` view and the runtime environment.

**Caveat**: This is an LCG view specific issue mostly. If **nothing from LCG is used** (like a pure ATLAS AnalysisBase environment, or an environment in a Linux container) then `--system-site-packages` by itself should be sufficient.

## How things work

`cvmfs-venv` provides a shim layer to manage activation and use of a Python virtual environment created with LCG view resources.
It does this by copying the structure of the `activate` scripts generated by Python's [`venv` module][venv docs].
When `venv` creates a virtual environment it generates a shell script under the virtual environment's directory tree at `bin/activate`.
This `activate` script controls and edits the shell environmental variables `PATH` and [`PYTHONHOME`][PYTHONHOME docs] &mdash; placing the virtual environment's `bin/` directory onto `PATH` and unsetting `PYTHONHOME` upon activation, and restoring their original values when `deactivate` is run.
`cvmfs-venv` simply extends this existing behavior to also place the virtual environment's `site-packages/` directory onto `PYTHONPATH` during activation and to remove it on deactivation.
This is done by injecting Bash snippets directly into the `bin/activate` script generated by `venv` at positions found relative to the manipulation of `PYTHONHOME`.

###  Advantages

* As `cvmfs-venv` is just altering the contents of the `venv` virtual environment's `bin/activate` script it is extending existing functionality and not trying to remake virtual environments.
* Once the virtual environment is setup and modified there is no additional dependency on the `cvmfs-venv` script that generated it.
   - While it saves time it is not needed. You can setup the environment again without it.
   ```console
   $ . cvmfs-venv --setup "lsetup 'views LCG_102 x86_64-centos7-gcc11-opt'" venv
   ```
   vs.
   ```console
   $ setupATLAS -3
   $ lsetup "views LCG_102 x86_64-centos7-gcc11-opt"
   $ . venv/bin/activate
   ```
* As the virtual environment  is **prepended** to `PYTHONPATH` all packages installed in the virtual environment are automatically given higher precedence over existing packages of the same name found in the LCG view.
   - If a package named `awkward` is found in the `venv` virtual environment and in the LCG view, `import awkward` with import it from the virtual environment.
* Python packages not installed in the `venv` virtual environment but installed in the LCG view (e.g. ROOT, XRootD) can still be accessed inside of the virtual environment.
   - **N.B.:** This is considered a "advantage" loosely, as it is only happening as a side effect of the isolation of the virtual environment being broken by the LCG view's `PYTHONPATH` manipulation.
* Through additional manipulation of `PYTHONPATH` and `PATH` with the added `cvmfs-venv-rebase` functionality, any software added to `PATH` or `PYTHONPATH` (e.g., by CVMFS or ATLAS software) while the virtual environment is active will persist on `PATH` or `PYTHONPATH` when the virtual environment is deactivated, allowing for a smoother interactive experience.
   - Example: If you want to use [`rucio`][rucio-site] both inside and outside of the virtual environment you can set it up either before sourcing the `bin/activate` script

   ```console
   $ setupATLAS -3
   $ lsetup "views LCG_102 x86_64-centos7-gcc11-opt"
   $ lsetup "rucio -w"  # PYTHONPATH is altered by lsetup
   $ command -v rucio  # rucio is found
   $ . venv/bin/activate
   (venv) $ command -v rucio  # rucio is found
   (venv) $ deactivate
   $ command -v rucio  # rucio is found
   ```

   or after, as `cvmfs-venv-rebase` will update path variables and keep the virtual environment's directory trees at the heads.

   ```console
   $ setupATLAS -3
   $ lsetup "views LCG_102 x86_64-centos7-gcc11-opt"
   $ . venv/bin/activate
   (venv) $ lsetup "rucio -w"  # PYTHONPATH is altered by lsetup
   (venv) $ command -v rucio  # rucio is found
   (venv) $ deactivate  # deactivate calls cvmfs-venv-rebase to persist non-venv paths
   $ command -v rucio  # rucio is found
   ```

### Disadvantages

* The isolation of a Python virtual environment is not recovered.
Python packages installed in the LCG view can still be accessed inside of the virtual environment.
This can result in packages from the LCG view meeting requirements of other dependencies during a package install or upgrade (depending on the [upgrade strategy][pip-docs-upgrade-strategy]) and installing older versions then expected.
   - Suggestion: When installing or upgrading with `pip` use the [`--ignore-installed` flag][pip-docs-ignore-installed].
   - Suggestion: When using [`pip list`][pip-docs-list] to inspect installed packages, use the `--local` flag to not list packages from the LCG view.
   ```
   (venv) $ python -m pip list --local
   ```
* As the Python version tied to the virtual environment is provided by LCG view, any changes to the LCG view version require setting up the Python virtual environment from scratch.
   - It is highly advised that your environment be controlled with strict `requirements.txt` and lock files (e.g. generated from [`pip-tools`][pip-tools] using `pip-compile`) making it reproducible and easy to setup again as a consequence.
   - Example:
   ```console
   (venv) $ python -m pip install --upgrade pip-tools
   (venv) $ echo "scipy==1.8.0" > requirements.txt  # define high level requirements
   (venv) $ pip-compile --generate-hashes --output-file requirements.lock requirements.txt  # Generate full environment lock file
   (venv) $ python -m pip install --no-deps --require-hashes --only-binary :all: --requirement requirements.lock  # secure-install for reproducibility
   ```
* Having all of the environment manipulation happen inside of the `venv`'s `bin/activate` script means that the virtual environment needs to be activated after any LCG view or ATLAS software (which make `PYTHONPATH` not empty) to trigger `PYTHONPATH` manipulation.
This essentially means that the virtual environment must not be activated first in any setup script.

## Citation

The preferred BibTeX entry for citation of `cvmfs-venv` is

```
@software{cvmfs-venv,
  author = {Matthew Feickert},
  title = "{cvmfs-venv: v0.0.3}",
  version = {0.0.3},
  doi = {10.5281/zenodo.7751033},
  url = {https://doi.org/10.5281/zenodo.7751033},
  note = {https://github.com/matthewfeickert/cvmfs-venv/releases/tag/v0.0.3}
}
```

[PYTHONHOME docs]: https://docs.python.org/3/using/cmdline.html#envvar-PYTHONHOME
[PYTHONPATH docs]: https://docs.python.org/3/using/cmdline.html#envvar-PYTHONPATH
[venv docs]: https://docs.python.org/3/tutorial/venv.html

[pip-docs-list]: https://pip.pypa.io/en/stable/cli/pip_list/#pip-list
[pip-docs-upgrade-strategy]: https://pip.pypa.io/en/stable/cli/pip_install/#cmdoption-upgrade-strategy
[pip-docs-ignore-installed]: https://pip.pypa.io/en/stable/cli/pip_install/#cmdoption-I

[pip-tools]: https://github.com/jazzband/pip-tools

[lcgenv]: https://gitlab.cern.ch/GENSER/lcgenv
[rucio-site]: https://rucio.cern.ch/
