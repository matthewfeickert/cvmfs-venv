#!/bin/bash

# Install cvmfs-venv
mkdir -p ~/.local/bin
export PATH=~/.local/bin:"${PATH}"  # If ~/.local/bin not on PATH already
curl -sL https://raw.githubusercontent.com/matthewfeickert/cvmfs-venv/main/cvmfs-venv.sh -o ~/.local/bin/cvmfs-venv
chmod +x ~/.local/bin/cvmfs-venv

# Guard against this being run in a subshell
export ATLAS_LOCAL_ROOT_BASE=/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase
. "${ATLAS_LOCAL_ROOT_BASE}/user/atlasLocalSetup.sh" -3 --quiet  # setuptATLAS

echo "# asetup AnalysisBase,22.2.113"
asetup AnalysisBase,22.2.113
echo "# cvmfs-venv atlas-ab-example"
cvmfs-venv atlas-ab-example
echo "# . atlas-ab-example/bin/activate"
. atlas-ab-example/bin/activate

echo "# python -m pip list"
python -m pip list
echo "# python -m pip show cython"
python -m pip show cython
echo "# python -m pip install --upgrade cython"
python -m pip install --upgrade cython
echo "# python -m pip list --local"
python -m pip list --local
echo "# python -m pip show cython"
python -m pip show cython
echo "# python -c 'import cython; print(cython.__version__)'"
python -c 'import cython; print(cython.__version__)'
echo "# python -c 'import ROOT; print(ROOT); import XRootD; print(XRootD)'"
python -c 'import ROOT; print(ROOT); import XRootD; print(XRootD)'
