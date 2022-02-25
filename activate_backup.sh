# This file must be used with "source bin/activate" *from bash*
# you cannot run it directly

deactivate () {
    # Added by https://github.com/matthewfeickert/cvmfs-venv
    cvmfs-venv-rebase

    # reset old environment variables
    if [ -n "${_OLD_VIRTUAL_PATH:-}" ] ; then
        PATH="${_OLD_VIRTUAL_PATH:-}"
        export PATH
        unset _OLD_VIRTUAL_PATH
    fi
    if [ -n "${_OLD_VIRTUAL_PYTHONHOME:-}" ] ; then
        PYTHONHOME="${_OLD_VIRTUAL_PYTHONHOME:-}"
        export PYTHONHOME
        unset _OLD_VIRTUAL_PYTHONHOME
    fi
    # Added by https://github.com/matthewfeickert/cvmfs-venv
    if [ -n "${_OLD_VIRTUAL_PYTHONPATH:-}" ] ; then
        PYTHONPATH="${_OLD_VIRTUAL_PYTHONPATH:-}"
        export PYTHONPATH
        unset _OLD_VIRTUAL_PYTHONPATH
        unset _VIRTUAL_SITE_PACKAGES
    fi

    # This should detect bash and zsh, which have a hash command that must
    # be called to get it to forget past commands.  Without forgetting
    # past commands the $PATH changes we made may not be respected
    if [ -n "${BASH:-}" -o -n "${ZSH_VERSION:-}" ] ; then
        hash -r 2> /dev/null
    fi

    if [ -n "${_OLD_VIRTUAL_PS1:-}" ] ; then
        PS1="${_OLD_VIRTUAL_PS1:-}"
        export PS1
        unset _OLD_VIRTUAL_PS1
    fi

    unset VIRTUAL_ENV
    if [ ! "${1:-}" = "nondestructive" ] ; then
    # Self destruct!
        unset -f deactivate
        # Added by https://github.com/matthewfeickert/cvmfs-venvunset
        unset -f cvmfs-venv-rebase
    fi
}

# Added by https://github.com/matthewfeickert/cvmfs-venv
cvmfs-venv-rebase () {
    # Reorder the PATH so that the virtual environment bin directory tree
    # is at the head.
    if [ -n "${_OLD_VIRTUAL_PATH:-}" ] ; then
        # Bracket with ":" for easier parsing
        _PATH=":${PATH}:"
        # Strip $VIRTUAL_ENV/bin from PATH
        VIRTUAL_ENV_BIN="${VIRTUAL_ENV}/bin"
        _PATH="${_PATH//:${VIRTUAL_ENV_BIN}:/:}"
        # Remove ":" from start and end of PATH
        _PATH="${_PATH#:}"
        _PATH="${_PATH%:}"
        # Update value of PATH to restore at deactivate
        _OLD_VIRTUAL_PATH="${_PATH}"
        # Prepend $VIRTUAL_ENV/bin to front of PATH
        _PATH="${VIRTUAL_ENV_BIN}:${_PATH}"
        export PATH="${_PATH}"

        unset VIRTUAL_ENV_BIN
        unset _PATH
    fi

    # Reorder the PYTHONPATH so that the virtual environment directory tree
    # is at the head.
    if [ -n "${_VIRTUAL_SITE_PACKAGES:-}" ] ; then
        # Bracket with ":" for easier parsing
        _PYTHONPATH=":${PYTHONPATH}:"
        # Strip _VIRTUAL_SITE_PACKAGES from PYTHONPATH
        _PYTHONPATH="${_PYTHONPATH//:${_VIRTUAL_SITE_PACKAGES}:/:}"
        # Remove ":" from start and end of PYTHONPATH
        _PYTHONPATH="${_PYTHONPATH#:}"
        _PYTHONPATH="${_PYTHONPATH%:}"
        # Update value of PYTHONPATH to restore at deactivate
        _OLD_VIRTUAL_PYTHONPATH="${_PYTHONPATH}"
        # Prepend _VIRTUAL_SITE_PACKAGES_DIRECTORY_TREE to front of PYTHONPATH
        _PYTHONPATH="${_VIRTUAL_SITE_PACKAGES}:${_PYTHONPATH}"
        export PYTHONPATH="${_PYTHONPATH}"

        unset _PYTHONPATH
    fi
}

# unset irrelevant variables
deactivate nondestructive

VIRTUAL_ENV="/home/feickert/debug/venv"
export VIRTUAL_ENV

_OLD_VIRTUAL_PATH="$PATH"
PATH="$VIRTUAL_ENV/bin:$PATH"
export PATH

# unset PYTHONHOME if set
# this will fail if PYTHONHOME is set to the empty string (which is bad anyway)
# could use `if (set -u; : $PYTHONHOME) ;` in bash
if [ -n "${PYTHONHOME:-}" ] ; then
    _OLD_VIRTUAL_PYTHONHOME="${PYTHONHOME:-}"
    unset PYTHONHOME
fi
# Added by https://github.com/matthewfeickert/cvmfs-venv
if [ -n "${PYTHONPATH:-}" ] ; then
    _OLD_VIRTUAL_PYTHONPATH="${PYTHONPATH:-}"
    unset PYTHONPATH
    unset _VIRTUAL_SITE_PACKAGES
    _VIRTUAL_SITE_PACKAGES="$(find ${VIRTUAL_ENV}/lib/ -type d -name site-packages)"
    export PYTHONPATH="${_VIRTUAL_SITE_PACKAGES}:${_OLD_VIRTUAL_PYTHONPATH}"
fi

if [ -z "${VIRTUAL_ENV_DISABLE_PROMPT:-}" ] ; then
    _OLD_VIRTUAL_PS1="${PS1:-}"
    PS1="(venv) ${PS1:-}"
    export PS1
fi

# This should detect bash and zsh, which have a hash command that must
# be called to get it to forget past commands.  Without forgetting
# past commands the $PATH changes we made may not be respected
if [ -n "${BASH:-}" -o -n "${ZSH_VERSION:-}" ] ; then
    hash -r 2> /dev/null
fi
