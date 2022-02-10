#!/bin/bash

# Ensure that pip can't install outside a virtual environment
export PIP_REQUIRE_VIRTUALENV=true

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
    _SET_PYTHONPATH=$(cat <<-EOT
    # Added by https://github.com/matthewfeickert/cvmfs-venv
    if [ -n "\${_OLD_VIRTUAL_PYTHONPATH:-}" ] ; then
        PYTHONPATH="\${_OLD_VIRTUAL_PYTHONPATH:-}"
        export PYTHONPATH
        unset _OLD_VIRTUAL_PYTHONPATH
    fi
EOT
)

    _RECOVER_OLD_PYTHONPATH=$(cat <<-EOT
# Added by https://github.com/matthewfeickert/cvmfs-venv
if [ -n "\${PYTHONPATH:-}" ] ; then
    _OLD_VIRTUAL_PYTHONPATH="\${PYTHONPATH:-}"
    unset PYTHONPATH
    export PYTHONPATH="\$(find \${VIRTUAL_ENV}/lib/ -type d -name site-packages):\${_OLD_VIRTUAL_PYTHONPATH}"
fi
EOT
)

    _SET_PYTHONPATH_INSERT_LINE="$(($(sed -n '\|unset _OLD_VIRTUAL_PYTHONHOME|=' ${_venv_name}/bin/activate) + 2))"
    ed --silent "$(readlink -f ${_venv_name}/bin/activate)" <<EOF
${_SET_PYTHONPATH_INSERT_LINE}i
${_SET_PYTHONPATH}
.
wq
EOF

    _RECOVER_OLD_PYTHONPATH_LINE="$(($(sed -n '\|    unset PYTHONHOME|=' ${_venv_name}/bin/activate) + 2))"
    ed --silent "$(readlink -f ${_venv_name}/bin/activate)" <<EOF
${_RECOVER_OLD_PYTHONPATH_LINE}i
${_RECOVER_OLD_PYTHONPATH}
.
wq
EOF

unset _SET_PYTHONPATH
unset _RECOVER_OLD_PYTHONPATH
unset _SET_PYTHONPATH_LINE
unset _RECOVER_OLD_PYTHONPATH_LINE

fi
. "${_venv_name}/bin/activate"

# Place venv's site-packages on PYTHONPATH to allow venv control of pip
#export PYTHONPATH="$(find $(dirname $(command -v python))/../ -type d -name site-packages):${PYTHONPATH}"
unset _venv_name
