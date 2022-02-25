# cvmfs-venv

Example implementation of getting a Python virtual environment to work with CVMFS [LCG views][LCG_info]. This is done by adding additional hooks to the Python virtual environment's `bin/activate` script.

[LCG_info]: https://lcginfo.cern.ch/

## Install

Either clone the repo to your directory or simply download the relevant files

```console
$ curl -sLO https://raw.githubusercontent.com/matthewfeickert/cvmfs-venv/main/atlas_setup.sh
```

## Use

Source the script to create a Python 3 virtual environment that can coexist with a CVMFS LCG view. The default name is `venv`.

```console
$ . atlas_setup.sh <name of your virtual environment>  # default name is 'venv'
```

### Example

```console
$ ssh lxplus
[feickert@lxplus732 ~]$ curl -sLO https://raw.githubusercontent.com/matthewfeickert/cvmfs-venv/main/atlas_setup.sh
[feickert@lxplus732 ~]$ . atlas_setup.sh example

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
Python 3.7.6 (default, Aug 12 2020, 09:46:40)
[GCC 8.3.0] on linux
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

When an LCG view or an ATLAS computing environment that uses software from CVFMS is setup it manipulates and alters the [`PYTHONPATH` environment variable][PYTHONPATH docs].
By placing the contents of all the installed software of an LCG view or ATLAS release onto `PYTHONPATH` for the rest of the shell session

`cvmfs-venv` is needed as there needs to be a shim layer

[PYTHONPATH docs]: https://docs.python.org/3/using/cmdline.html#envvar-PYTHONPATH

## How things work
