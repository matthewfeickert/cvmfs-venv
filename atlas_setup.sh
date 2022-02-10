#!/bin/bash

# Check to see if we need to run setupATLAS
command -v lsetup > /dev/null
if [ "$?" == "1" ]; then
    export ATLAS_LOCAL_ROOT_BASE=/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase
    # Allows for working with wrappers as well
    . "${ATLAS_LOCAL_ROOT_BASE}/user/atlasLocalSetup.sh" --quiet || echo "~~~ERROR: setupATLAS failed!~~~"
fi

# Setup default LCG view
default_LCG_release="LCG_98python3"
default_LCG_platform="x86_64-centos7-gcc8-opt"
printf "\nlsetup 'views ${default_LCG_release} ${default_LCG_platform}'\n"
lsetup "views ${default_LCG_release} ${default_LCG_platform}"

_venv_name="${1:-venv}"
if [ ! -d "${_venv_name}" ]; then
    printf "# Creating new Python virtual environment ${_venv_name}\n"
    python3 -m venv "${_venv_name}"
    # Do manipulation of activate script
fi
. "${_venv_name}/bin/activate"

# Place venv's site-packages on PYTHONPATH to allow venv control of pip
#export PYTHONPATH="$(find $(dirname $(command -v python))/../ -type d -name site-packages):${PYTHONPATH}"
unset _venv_name
