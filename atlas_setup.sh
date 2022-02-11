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
# Check if on a CentOS 8 machine
if [ "$(python3 -c 'from platform import platform; print("centos-8" in platform())')" == "True" ]; then
    default_LCG_release="LCG_100"
    default_LCG_platform="x86_64-centos8-gcc10-opt"
fi
printf "\nlsetup 'views %s %s'\n" "${default_LCG_release}" "${default_LCG_platform}"
lsetup "views ${default_LCG_release} ${default_LCG_platform}"

_venv_name="${1:-venv}"
if [ ! -d "${_venv_name}" ]; then
    printf "# Creating new Python virtual environment '%s'\n" "${_venv_name}"
    python3 -m venv "${_venv_name}"

    # When setting up the Python virtual environment shell variables in the
    # main section of the <venv>/bin/activate script, copy the pattern used
    # for PYTHONHOME to also place the <venv>'s site-packages at the front
    # of PYTHONPATH so that they are ahead of the LCG view's packages in
    # priority.
    _SET_PYTHONPATH=$(cat <<-EOT
# Added by https://github.com/matthewfeickert/cvmfs-venv
if [ -n "\${PYTHONPATH:-}" ] ; then
    _OLD_VIRTUAL_PYTHONPATH="\${PYTHONPATH:-}"
    unset PYTHONPATH
    export PYTHONPATH="\$(find \${VIRTUAL_ENV}/lib/ -type d -name site-packages):\${_OLD_VIRTUAL_PYTHONPATH}"
fi
EOT
)

    # When deactivate is being run, reset the PYTHONPATH to what is was before
    # activation of the Python virtual environment. This ensures that the <venv>'s
    # site-packages are removed from PYTHONPATH so there is no collision if
    # attempting to use a different virtual environment or if attempting to use
    # the LCG view's packages.
    _RECOVER_OLD_PYTHONPATH=$(cat <<-EOT
    # Added by https://github.com/matthewfeickert/cvmfs-venv
    if [ -n "\${_OLD_VIRTUAL_PYTHONPATH:-}" ] ; then
        PYTHONPATH="\${_OLD_VIRTUAL_PYTHONPATH:-}"
        export PYTHONPATH
        unset _OLD_VIRTUAL_PYTHONPATH
    fi
EOT
)

    # Find the line number of the last line in the PYTHONHOME set if statement
    # block and inject the PYTHONPATH if statement block directly after it
    # (2 lines later).
    _RECOVER_OLD_PYTHONPATH_LINE="$(($(sed -n '\|unset _OLD_VIRTUAL_PYTHONHOME|=' "${_venv_name}"/bin/activate) + 2))"
    ed --silent "$(readlink -f "${_venv_name}"/bin/activate)" <<EOF
${_SET_PYTHONPATH_INSERT_LINE}i
${_SET_PYTHONPATH}
.
wq
EOF

    # Find the line number of the last line in deactivate's PYTHONHOME reset
    # if statement block and inject the PYTHONPATH reset if statement block directly
    # after it (2 lines later).
    _SET_PYTHONPATH_INSERT_LINE="$(($(sed -n '\|    unset PYTHONHOME|=' "${_venv_name}"/bin/activate) + 2))"
    ed --silent "$(readlink -f "${_venv_name}"/bin/activate)" <<EOF
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

# Activate the virtual environment
. "${_venv_name}/bin/activate"

# Get latest pip, setuptools, wheel
# Hide not-real errors from CVMFS by sending to /dev/null
python -m pip --quiet install --upgrade pip setuptools wheel &> /dev/null

unset _venv_name
