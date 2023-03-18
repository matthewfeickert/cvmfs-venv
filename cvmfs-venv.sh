#!/bin/bash

# Ensure that pip can't install outside a virtual environment
export PIP_REQUIRE_VIRTUALENV=true

if [ -d "/cvmfs/atlas.cern.ch" ]; then
    # Check to see if we need to run setupATLAS
    command -v lsetup > /dev/null
    if [ "$?" == "1" ]; then
        export ATLAS_LOCAL_ROOT_BASE=/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase
        # Allows for working with wrappers as well
        . "${ATLAS_LOCAL_ROOT_BASE}/user/atlasLocalSetup.sh" -3 --quiet || echo '~~~ERROR: setupATLAS failed!~~~'
    fi

    # Setup default LCG view
    default_LCG_release="LCG_101"
    default_LCG_platform="x86_64-centos7-gcc10-opt"
    # Check if on a CentOS 8 machine
    if [ "$(python3 -c 'from platform import platform; print("centos-8" in platform())')" == "True" ]; then
        default_LCG_release="LCG_101"
        default_LCG_platform="x86_64-centos8-gcc11-opt"
    fi
    printf "\nlsetup 'views %s %s'\n" "${default_LCG_release}" "${default_LCG_platform}"
    lsetup "views ${default_LCG_release} ${default_LCG_platform}"

elif [ -f "/release_setup.sh" ]; then
    # If in Linux container
    . /release_setup.sh
fi

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
    unset _VIRTUAL_SITE_PACKAGES
    _VIRTUAL_SITE_PACKAGES="\$(find \${VIRTUAL_ENV}/lib/ -type d -name site-packages)"
    export PYTHONPATH="\${_VIRTUAL_SITE_PACKAGES}:\${_OLD_VIRTUAL_PYTHONPATH}"
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
        unset _VIRTUAL_SITE_PACKAGES
    fi
EOT
)

    # When deactivate is being run, run cvmfs-venv-rebase as the very first action
    # to ensure that _OLD_VIRTUAL_PYTHONPATH is updated to the current value of
    # PYTHONPATH so that software loaded with CVMFS is still available when
    # the virtual environment is deactivated.
    # c.f. https://unix.stackexchange.com/a/534073/275785
    nl=$'\n'
    _RUN_REBASE=$(cat <<-EOT
    # Added by https://github.com/matthewfeickert/cvmfs-venv
    cvmfs-venv-rebase  # Keep lsetup PATHs added while venv active
    $nl
EOT
)
    unset nl

    # If the deactivate is being run in a destructive manner (i.e., anytime that isn't
    # the sanitizing pass through on activate) then unset cvmfs-venv-rebase.
    _DESCTRUCTIVE_UNSET=$(cat <<-EOT
        # Added by https://github.com/matthewfeickert/cvmfs-venv
        unset -f cvmfs-venv-rebase
EOT
)

    # Add in functionality to:
    # * Rebase the virtual environment's PATH and PYTHONPATH directory trees
    # to the head of those environment variables.
    # * Update the value of _OLD_VIRTUAL_PATH and _OLD_VIRTUAL_PYTHONPATH
    # to allow for software added to them from inside the virtual environment
    # to be usable outside.
    _CVMFS_VENV_REBASE=$(cat <<-EOT
# Added by https://github.com/matthewfeickert/cvmfs-venv
cvmfs-venv-rebase () {
    # Reorder the PATH so that the virtual environment bin directory tree
    # is at the head.
    if [ -n "\${_OLD_VIRTUAL_PATH:-}" ] ; then
        # Bracket with ":" for easier parsing
        _PATH=":\${PATH}:"
        # Strip \$VIRTUAL_ENV/bin from PATH
        VIRTUAL_ENV_BIN="\${VIRTUAL_ENV}/bin"
        _PATH="\${_PATH//:\${VIRTUAL_ENV_BIN}:/:}"
        # Remove ":" from start and end of PATH
        _PATH="\${_PATH#:}"
        _PATH="\${_PATH%:}"
        # Update value of PATH to restore at deactivate
        _OLD_VIRTUAL_PATH="\${_PATH}"
        # Prepend \$VIRTUAL_ENV/bin to front of PATH
        _PATH="\${VIRTUAL_ENV_BIN}:\${_PATH}"
        export PATH="\${_PATH}"

        unset VIRTUAL_ENV_BIN
        unset _PATH
    fi

    # Reorder the PYTHONPATH so that the virtual environment directory tree
    # is at the head.
    if [ -n "\${_VIRTUAL_SITE_PACKAGES:-}" ] ; then
        # Bracket with ":" for easier parsing
        _PYTHONPATH=":\${PYTHONPATH}:"
        # Strip _VIRTUAL_SITE_PACKAGES from PYTHONPATH
        _PYTHONPATH="\${_PYTHONPATH//:\${_VIRTUAL_SITE_PACKAGES}:/:}"
        # Remove ":" from start and end of PYTHONPATH
        _PYTHONPATH="\${_PYTHONPATH#:}"
        _PYTHONPATH="\${_PYTHONPATH%:}"
        # Update value of PYTHONPATH to restore at deactivate
        _OLD_VIRTUAL_PYTHONPATH="\${_PYTHONPATH}"
        # Prepend _VIRTUAL_SITE_PACKAGES_DIRECTORY_TREE to front of PYTHONPATH
        _PYTHONPATH="\${_VIRTUAL_SITE_PACKAGES}:\${_PYTHONPATH}"
        export PYTHONPATH="\${_PYTHONPATH}"

        unset _PYTHONPATH
    fi
}
EOT
)

    # Find the line number of the last line in the PYTHONHOME set if statement
    # block and inject the PYTHONPATH if statement block directly after it
    # (2 lines later).
    _RECOVER_OLD_PYTHONPATH_LINE="$(($(sed -n '\|unset _OLD_VIRTUAL_PYTHONHOME|=' "${_venv_name}"/bin/activate) + 2))"
    ed --silent "$(readlink -f "${_venv_name}"/bin/activate)" <<EOF
${_RECOVER_OLD_PYTHONPATH_LINE}i
${_RECOVER_OLD_PYTHONPATH}
.
wq
EOF

    # Find the line number of the last line in deactivate's PYTHONHOME reset
    # if statement block and inject the PYTHONPATH reset if statement block directly
    # after it (2 lines later).
    _SET_PYTHONPATH_INSERT_LINE="$(($(sed -n '\|    unset PYTHONHOME|=' "${_venv_name}"/bin/activate) + 2))"
    ed --silent "$(readlink -f "${_venv_name}"/bin/activate)" <<EOF
${_SET_PYTHONPATH_INSERT_LINE}i
${_SET_PYTHONPATH}
.
wq
EOF

    # Find the line number of the deactivate function and inject the cvmfs-venv-rebase directly after it
    # (1 line later).
    _RUN_REBASE_LINE="$(($(sed -n '\|deactivate ()|=' "${_venv_name}"/bin/activate) + 1))"
    ed --silent "$(readlink -f "${_venv_name}"/bin/activate)" <<EOF
${_RUN_REBASE_LINE}i
${_RUN_REBASE}
.
wq
EOF

    # Find the line number of the unset -f deactivate line in deactivate's destructive unset
    # and inject the cvmfs-venv-rebase reset directly after it (1 line later).
    _DESCTRUCTIVE_UNSET_LINE="$(($(sed -n '\|unset -f deactivate|=' "${_venv_name}"/bin/activate) + 1))"
    ed --silent "$(readlink -f "${_venv_name}"/bin/activate)" <<EOF
${_DESCTRUCTIVE_UNSET_LINE}i
${_DESCTRUCTIVE_UNSET}
.
wq
EOF

    # Find the line number of the unset -f cvmfs-venv-rebase line in deactivate's destructive unset
    # and inject the cvmfs-venv-rebase function directly after it (4 lines later).
    _CVMFS_VENV_REBASE_LINE="$(($(sed -n '\|unset -f cvmfs-venv-rebase|=' "${_venv_name}"/bin/activate) + 4))"
    ed --silent "$(readlink -f "${_venv_name}"/bin/activate)" <<EOF
${_CVMFS_VENV_REBASE_LINE}i
${_CVMFS_VENV_REBASE}
.
wq
EOF

unset _SET_PYTHONPATH
unset _RECOVER_OLD_PYTHONPATH
unset _RUN_REBASE
unset _DESCTRUCTIVE_UNSET
unset _CVMFS_VENV_REBASE

unset _SET_PYTHONPATH_LINE
unset _RECOVER_OLD_PYTHONPATH_LINE
unset _RUN_REBASE_LINE
unset _DESCTRUCTIVE_UNSET_LINE
unset _CVMFS_VENV_REBASE_LINE

fi

# Activate the virtual environment
. "${_venv_name}/bin/activate"

# Get latest pip, setuptools, wheel
# Hide not-real errors from CVMFS by sending to /dev/null
python -m pip --quiet install --upgrade pip setuptools wheel &> /dev/null

unset _venv_name
