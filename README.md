# cvmfs-venv

Example implementation of getting a Python virtual environment to work with CVMFS [LCG views][LCG_info]. This is done by adding additional hooks to the Python virtual environment's `bin/activate` script.

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
$ cvmfs-venv <name of your virtual environment>  # default name is 'venv'
```

### Example

```console
$ ssh lxplus
[feickert@lxplus732 ~]$ mkdir -p ~/.local/bin
[feickert@lxplus732 ~]$ export PATH=~/.local/bin:"${PATH}"
[feickert@lxplus732 ~]$ curl -sL https://raw.githubusercontent.com/matthewfeickert/cvmfs-venv/main/cvmfs-venv.sh -o ~/.local/bin/cvmfs-venv
[feickert@lxplus732 ~]$ chmod +x ~/.local/bin/cvmfs-venv
[feickert@lxplus732 ~]$ cvmfs-venv example

lsetup 'views LCG_101 x86_64-centos7-gcc10-opt'
************************************************************************
Requested:  views ...
 Setting up views LCG_101:x86_64-centos7-gcc10-opt ...
>>>>>>>>>>>>>>>>>>>>>>>>> Information for user <<<<<<<<<<<<<<<<<<<<<<<<<
************************************************************************
# Creating new Python virtual environment 'example'
(example) [feickert@lxplus732 ~]$ python -m pip show lhapdf  # Still have full LCG view
Name: LHAPDF
Version: 6.3.0
Summary: UNKNOWN
Home-page: UNKNOWN
Author: UNKNOWN
Author-email: UNKNOWN
License: UNKNOWN
Location: /cvmfs/sft.cern.ch/lcg/views/LCG_101/x86_64-centos7-gcc10-opt/lib/python3.9/site-packages
Requires:
Required-by:
(example) [feickert@lxplus732 ~]$ python -m pip install --upgrade awkward  # This will show a false ERROR given CVFMS is in PYTHONPATH
(example) [feickert@lxplus732 ~]$ python
Python 3.9.6 (default, Sep  6 2021, 15:35:00)
[GCC 10.3.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import ROOT
>>> import XRootD
>>> import awkward
>>> exit()
(example) [feickert@lxplus732 ~]$ python -m pip show awkward  # Get version installed in venv
Name: awkward
Version: 1.7.0
Summary: Manipulate JSON-like data with NumPy-like idioms.
Home-page: https://github.com/scikit-hep/awkward-1.0
Author: Jim Pivarski
Author-email: pivarski@princeton.edu
License: BSD-3-Clause
Location: /afs/cern.ch/user/f/feickert/example/lib/python3.9/site-packages
Requires: numpy, setuptools
Required-by:
(example) [feickert@lxplus732 ~]$ python -m pip list --local  # View of virtual environment controlled packages
Package    Version
---------- -------
awkward    1.7.0
pip        22.0.3
setuptools 60.9.3
wheel      0.37.1
(example) [feickert@lxplus732 ~]$ deactivate  # Resets PYTHONPATH given added hooks
[feickert@lxplus732 ~]$ python -m pip show awkward  # Get CVMFS's old version
Name: awkward
Version: 1.0.2
Summary: Manipulate JSON-like data with NumPy-like idioms.
Home-page: https://github.com/scikit-hep/awkward-1.0
Author: Jim Pivarski
Author-email: pivarski@princeton.edu
License: BSD 3-clause
Location: /cvmfs/sft.cern.ch/lcg/views/LCG_101/x86_64-centos7-gcc10-opt/lib/python3.9/site-packages
Requires: setuptools, numpy
Required-by:
```

## Why is this needed?

When an LCG view or an ATLAS computing environment that uses software from CVFMS is setup, it manipulates and alters the [`PYTHONPATH` environment variable][PYTHONPATH docs].
By placing the contents of all the installed software of an LCG view or ATLAS release onto `PYTHONPATH` for the rest of the shell session, the protections and isolation of a Python virtual environment are broken.
It is not possible to fix this in a reliable and robust way that will not break the access of other software in the LCG view or ATLAS environment dependent on the Python packages in them.
The best that can be done is to control the directory tree at the **head** of `PYTHONPATH` in a stable manner that allows for most of the benefits of a Python virtual environment (control of install and versions of packages, isolation of directory tree).

While [`lcgenv`][lcgenv] allows for package specific environment building, it still lacks the control to specify arbitrary versions of Python packages and will load additional libraries beyond what is strictly required by the target package dependency requirements.
That being said, if you are able to use an LCG view or `lcgenv` without any additional setup, you may not have need of specifying a Python virtual environment.

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
   $ cvmfs-venv venv
   ```
   vs.
   ```console
   $ setupATLAS -3
   $ lsetup "views LCG_101 x86_64-centos7-gcc10-opt"
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
   $ lsetup "views LCG_101 x86_64-centos7-gcc10-opt"
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
   $ lsetup "views LCG_101 x86_64-centos7-gcc10-opt"
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

[PYTHONHOME docs]: https://docs.python.org/3/using/cmdline.html#envvar-PYTHONHOME
[PYTHONPATH docs]: https://docs.python.org/3/using/cmdline.html#envvar-PYTHONPATH
[venv docs]: https://docs.python.org/3/tutorial/venv.html

[pip-docs-list]: https://pip.pypa.io/en/stable/cli/pip_list/#pip-list
[pip-docs-upgrade-strategy]: https://pip.pypa.io/en/stable/cli/pip_install/#cmdoption-upgrade-strategy
[pip-docs-ignore-installed]: https://pip.pypa.io/en/stable/cli/pip_install/#cmdoption-I

[pip-tools]: https://github.com/jazzband/pip-tools

[lcgenv]: https://gitlab.cern.ch/GENSER/lcgenv
[rucio-site]: https://rucio.cern.ch/
