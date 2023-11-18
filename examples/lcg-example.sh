#!/bin/bash

# Install cvmfs-venv
mkdir -p ~/.local/bin
export PATH=~/.local/bin:"${PATH}"  # If ~/.local/bin not on PATH already
curl -sL https://raw.githubusercontent.com/matthewfeickert/cvmfs-venv/main/cvmfs-venv.sh -o ~/.local/bin/cvmfs-venv
chmod +x ~/.local/bin/cvmfs-venv

# Guard against this being run in a subshell
export ATLAS_LOCAL_ROOT_BASE=/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase
. "${ATLAS_LOCAL_ROOT_BASE}/user/atlasLocalSetup.sh" -3 --quiet  # setuptATLAS

echo "# lsetup 'views LCG_104 x86_64-centos7-gcc12-opt'"
lsetup 'views LCG_104 x86_64-centos7-gcc12-opt'
echo "# cvmfs-venv lcg-example"
cvmfs-venv lcg-example
echo "# . lcg-example/bin/activate"
. lcg-example/bin/activate

echo "# python -m pip list --local"
python -m pip list --local
echo "# python -m pip show awkward"
python -m pip show awkward
echo "# python -m pip install --upgrade awkward"
python -m pip install --upgrade awkward
echo "# python -m pip list --local"
python -m pip list --local
echo "# python -m pip show awkward"
python -m pip show awkward
echo "# python -c 'import awkward; print(awkward.__version__)'"
python -c 'import awkward; print(awkward.__version__)'
