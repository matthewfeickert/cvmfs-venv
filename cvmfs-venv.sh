#!/bin/bash
#
# cvmfs-venv: create a Python virtual environment that can coexist with
# software set up from CVMFS (LCG views, ATLAS releases).
#
# This file can be executed (`cvmfs-venv <name>`) or sourced
# (`. cvmfs-venv --setup '...' <name>`). All work happens inside
# _cvmfs_venv_main so that errors `return` rather than `exit` (which would
# terminate a sourcing shell), working variables stay local, and the exit
# status reaches the caller in both modes.

_cvmfs_venv_help () {
    cat <<EOF
Usage: cvmfs-venv [-s|--setup] [--no-system-site-packages] [--no-update] [--no-uv] <virtual environment name>

Options:
 -h --help      Print this help message
 -s --setup     String of setup options to be parsed
 --no-system-site-packages
                The venv module '--system-site-packages' option is used by
                default. While it is not recommended, this behavior can be
                disabled through use of this flag.
 --no-update    After venv creation don't update pip and setuptools to the
                latest releases. Use of this option is not recommended,
                but is faster.
 --no-uv        After venv creation don't install uv and use it to update pip,
                and setuptools. By default, uv is installed.

Note: cvmfs-venv extends the Python venv module and so requires Python 3.4+.

Examples:

    * Create a Python 3 virtual environment named 'lcg-example' with the Python
    runtime provided by LCG view 105 on AlmaLinux 9.

        setupATLAS -3
        lsetup 'views LCG_105 x86_64-el9-gcc12-opt'
        cvmfs-venv lcg-example
        . lcg-example/bin/activate

    * Create a Python 3 virtual environment named 'atlas-ab-example' with the
    Python runtime provided by ATLAS AnalysisBase release v25.2.15.

        setupATLAS -3
        asetup AnalysisBase,25.2.15
        cvmfs-venv atlas-ab-example
        . atlas-ab-example/bin/activate

    * Create a Python 3 virtual environment named 'venv' with whatever Python
    runtime "\$(command -v python3)" evaluates to.

        cvmfs-venv
        . venv/bin/activate

    * Setup LCG view 105 on AlmaLinux 9 and create a Python virtual environment
    named 'lcg-example' using the Python 3.9 runtime it provides.

        . cvmfs-venv --setup "lsetup 'views LCG_105 x86_64-el9-gcc12-opt'" lcg-example

    * Setup ATLAS AnalysisBase release v25.2.15 and create a Python virtual
    environment named 'atlas-ab-example' using the Python 3.9 runtime it
    provides.

        . cvmfs-venv --setup 'asetup AnalysisBase,25.2.15' atlas-ab-example
EOF
    return 0
}

# _cvmfs_venv_patch_activate <python> <file> [<anchor> <offset> <after> <text>]...
#
# Insert each <text> into <file> before the line <offset> lines after the
# single line whose stripped content equals <anchor>, requiring the line just
# before the insertion point to be exactly <after>. Every insertion is checked
# before anything is written and the file is then replaced in one step, so a
# changed venv activate template leaves it untouched and is reported instead
# of producing a silently broken environment. A trailing newline on <text>
# gives a blank line after the inserted block.
#
# The literal @CVMFS_VENV_SITE_PACKAGES@ in a <text> is replaced by the
# environment's site-packages directory relative to the environment. It is
# computed here rather than captured from stdout because .pth files and
# sitecustomize can print during interpreter start-up.
#
# Runs under the environment's own Python, which is always present, so no
# external editor is needed. Isolated mode (-I, Python 3.4+) matters: the
# script runs after lsetup/asetup have set PYTHONPATH, and PYTHONHOME must not
# steer a venv interpreter.
_cvmfs_venv_patch_activate () {
    "${1}" -I - "${@:2}" <<'PY'
import os
import sys
import sysconfig

path = sys.argv[1]
edits = sys.argv[2:]
if not edits or len(edits) % 4:
    sys.exit("ERROR: expected groups of anchor, offset, after, text")

site_packages = sysconfig.get_path("purelib")
if not os.path.isdir(site_packages):
    sys.exit("ERROR: site-packages directory %r does not exist" % site_packages)
site_packages = os.path.relpath(site_packages, sys.prefix)

# surrogateescape and newline="" preserve every byte venv wrote
with open(path, encoding="utf-8", errors="surrogateescape", newline="") as activate:
    lines = activate.readlines()

for start in range(0, len(edits), 4):
    anchor, offset, after, text = edits[start:start + 4]
    hits = [index for index, line in enumerate(lines) if line.strip() == anchor]
    if len(hits) != 1:
        sys.exit(
            "ERROR: expected exactly one line %r in %s, found %d"
            % (anchor, path, len(hits))
        )
    position = hits[0] + int(offset)
    previous = lines[position - 1].rstrip("\r\n") if position > 0 else None
    if previous != after:
        sys.exit(
            "ERROR: expected %r before the insertion point %s lines after %r in %s, found %r"
            % (after, offset, anchor, path, previous)
        )
    lines.insert(position, text.replace("@CVMFS_VENV_SITE_PACKAGES@", site_packages) + "\n")

temporary = path + ".cvmfs-venv"
with open(temporary, "w", encoding="utf-8", errors="surrogateescape", newline="") as activate:
    activate.writelines(lines)
os.chmod(temporary, os.stat(path).st_mode & 0o7777)
os.replace(temporary, path)
PY
}

_cvmfs_venv_main () {
    local _setup_command=""
    local _no_system_site_packages=""
    local _no_update=""
    local _no_uv=""
    local _do_setup_atlas=""
    local _venv_name=""
    local _venv_full_path=""
    local _venv_python=""
    local _activate=""
    local _SET_PYTHONPATH="" _RECOVER_OLD_PYTHONPATH="" _RUN_REBASE=""
    local _DESTRUCTIVE_UNSET="" _CVMFS_VENV_REBASE=""

    # CLI API
    while [ $# -gt 0 ]; do
        case "${1}" in
            -h|--help)
                _cvmfs_venv_help
                return 0
                ;;
            -s|--setup)
                _setup_command="${2:-}"
                shift 2
                ;;
            --no-system-site-packages)
                _no_system_site_packages=true
                shift
                ;;
            --no-update)
                _no_update=true
                shift
                ;;
            --no-uv)
                _no_uv=true
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                if [ $# -eq 1 ]; then
                    #FIXME: Needs better guard
                    if [[ "${1}" != *"--"* ]]; then
                        # this is the venv's name
                        break
                    fi
                fi
                echo "ERROR: Invalid option '${1}'" >&2
                return 1
                ;;
        esac
    done

    if [ -n "${_setup_command}" ]; then
        if [ -f "/release_setup.sh" ]; then
            # If in Linux container
            if [[ "${_setup_command}" != *"/release_setup.sh"* ]]; then
                echo "WARNING: /release_setup.sh exists and it is assumed you are in a Linux container."
                echo "         '${_setup_command}' will be skipped in favor of using '. /release_setup.sh'."
            fi
            printf "\n. /release_setup.sh\n"
            # shellcheck source=/dev/null
            . /release_setup.sh
        else
            # Try to setup an environment using CVMFS
            _do_setup_atlas=false
            if [[ "${_setup_command}" == *"lsetup"* ]]; then
                _do_setup_atlas=true
            fi
            if [[ "${_setup_command}" == *"asetup"* ]]; then
                _do_setup_atlas=true
            fi

            if [ "${_do_setup_atlas}" = true ]; then
                if [ -d "/cvmfs/atlas.cern.ch" ]; then
                    # Check to see if we need to run setupATLAS
                    if ! command -v lsetup > /dev/null 2>&1; then
                        export ATLAS_LOCAL_ROOT_BASE=/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase
                        # Allows for working with wrappers as well
                        # shellcheck source=/dev/null
                        . "${ATLAS_LOCAL_ROOT_BASE}/user/atlasLocalSetup.sh" -3 --quiet || echo '~~~ERROR: setupATLAS failed!~~~'
                    fi

                    printf '\n%s\n' "${_setup_command}"
                    eval "${_setup_command}"
                else
                    echo "ERROR: /cvmfs/atlas.cern.ch/ not found. Check that CernVM-FS is mounted correctly." >&2
                    return 1
                fi
            fi
        fi
    # If in Linux container
    elif [ -f "/release_setup.sh" ]; then
        echo "WARNING: /release_setup.sh exists and it is assumed you are in a Linux container."
        echo "         Setting up environment with '. /release_setup.sh'."
        printf "\n. /release_setup.sh\n"
        # shellcheck source=/dev/null
        . /release_setup.sh
    fi

    # Ensure that pip can't install outside a virtual environment
    export PIP_REQUIRE_VIRTUALENV=true

    _venv_name="${1:-venv}"
    if [ ! -d "${_venv_name}" ]; then
        printf "# Creating new Python virtual environment '%s'\n" "${_venv_name}"
        # Default to using --system-site-packages to add extra guards
        if [ -z "${_no_system_site_packages}" ]; then
            python3 -m venv --system-site-packages "${_venv_name}"
        else
            python3 -m venv "${_venv_name}"
        fi
        _venv_full_path="$(readlink -f "${_venv_name}")"
        _venv_python="${_venv_full_path}/bin/python"
        _activate="${_venv_full_path}/bin/activate"

        # When setting up the Python virtual environment shell variables in the
        # main section of the <venv>/bin/activate script, copy the pattern used
        # for PYTHONHOME to also place the <venv>'s site-packages at the front
        # of PYTHONPATH so that they are ahead of the LCG view's packages in
        # priority. The site-packages directory (relative to the environment)
        # is fixed at creation time, just as venv fixes VIRTUAL_ENV, so
        # activation needs no filesystem search.
        _SET_PYTHONPATH=$(cat <<EOT
# Added by https://github.com/matthewfeickert/cvmfs-venv
if [ -n "\${PYTHONPATH:-}" ] ; then
    _OLD_VIRTUAL_PYTHONPATH="\${PYTHONPATH:-}"
    _VIRTUAL_SITE_PACKAGES="\${VIRTUAL_ENV}/@CVMFS_VENV_SITE_PACKAGES@"
    PYTHONPATH="\${_VIRTUAL_SITE_PACKAGES}:\${_OLD_VIRTUAL_PYTHONPATH}"
    export PYTHONPATH
fi
EOT
)

        # When deactivate is being run, reset the PYTHONPATH to what is was before
        # activation of the Python virtual environment. This ensures that the <venv>'s
        # site-packages are removed from PYTHONPATH so there is no collision if
        # attempting to use a different virtual environment or if attempting to use
        # the LCG view's packages.
        _RECOVER_OLD_PYTHONPATH=$(cat <<EOT
    # Added by https://github.com/matthewfeickert/cvmfs-venv
    if [ -n "\${_VIRTUAL_SITE_PACKAGES:-}" ] ; then
        if [ -n "\${_OLD_VIRTUAL_PYTHONPATH:-}" ] ; then
            PYTHONPATH="\${_OLD_VIRTUAL_PYTHONPATH:-}"
            export PYTHONPATH
        else
            unset PYTHONPATH
        fi
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
        _RUN_REBASE=$(cat <<EOT
    # Added by https://github.com/matthewfeickert/cvmfs-venv
    cvmfs-venv-rebase  # Keep lsetup PATHs added while venv active
EOT
)

        # If the deactivate is being run in a destructive manner (i.e., anytime that isn't
        # the sanitizing pass through on activate) then unset cvmfs-venv-rebase.
        _DESTRUCTIVE_UNSET=$(cat <<EOT
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
        _CVMFS_VENV_REBASE=$(cat <<EOT
# Added by https://github.com/matthewfeickert/cvmfs-venv
cvmfs-venv-rebase () {
    # Reorder the PATH so that the virtual environment bin directory tree
    # is at the head.
    if [ -n "\${_OLD_VIRTUAL_PATH:-}" ] ; then
        # Bracket with ":" for easier parsing
        _PATH=":\${PATH}:"
        # Strip \$VIRTUAL_ENV/bin from PATH
        VIRTUAL_ENV_BIN="\${VIRTUAL_ENV}/bin"
        _PATH="\${_PATH//":\${VIRTUAL_ENV_BIN}:"/:}"
        # Remove ":" from start and end of PATH
        _PATH="\${_PATH#:}"
        _PATH="\${_PATH%:}"
        # Update value of PATH to restore at deactivate
        _OLD_VIRTUAL_PATH="\${_PATH}"
        # Prepend \$VIRTUAL_ENV/bin to front of PATH
        # In the event that VIRTUAL_ENV_BIN already happened
        # to be at the head of PATH, do nothing to avoid
        # having the same directory path twice consecutively.
        if [ "\${_PATH%%:*}" != "\${VIRTUAL_ENV_BIN}" ] ; then
            _PATH="\${VIRTUAL_ENV_BIN}:\${_PATH}"
        fi
        export PATH="\${_PATH}"

        unset VIRTUAL_ENV_BIN
        unset _PATH
    fi

    # Reorder the PYTHONPATH so that the virtual environment directory tree
    # is at the head. Skipped when PYTHONPATH was emptied while the
    # environment was active, so that deactivate restores the original value.
    if [ -n "\${_VIRTUAL_SITE_PACKAGES:-}" ] && [ -n "\${PYTHONPATH:-}" ] ; then
        # Bracket with ":" for easier parsing
        _PYTHONPATH=":\${PYTHONPATH}:"
        # Strip _VIRTUAL_SITE_PACKAGES from PYTHONPATH (quoted: literal, not a glob)
        _PYTHONPATH="\${_PYTHONPATH//":\${_VIRTUAL_SITE_PACKAGES}:"/:}"
        # Remove ":" from start and end of PYTHONPATH
        _PYTHONPATH="\${_PYTHONPATH#:}"
        _PYTHONPATH="\${_PYTHONPATH%:}"
        # Update value of PYTHONPATH to restore at deactivate
        _OLD_VIRTUAL_PYTHONPATH="\${_PYTHONPATH}"
        # Prepend _VIRTUAL_SITE_PACKAGES to front of PYTHONPATH, without
        # creating an empty element (which Python reads as the working
        # directory) and without repeating it when it is already at the head.
        if [ -z "\${_PYTHONPATH}" ] ; then
            _PYTHONPATH="\${_VIRTUAL_SITE_PACKAGES}"
        elif [ "\${_PYTHONPATH%%:*}" != "\${_VIRTUAL_SITE_PACKAGES}" ] ; then
            _PYTHONPATH="\${_VIRTUAL_SITE_PACKAGES}:\${_PYTHONPATH}"
        fi
        export PYTHONPATH="\${_PYTHONPATH}"

        unset _PYTHONPATH
    fi
}
EOT
)

        # Insert the snippets at positions relative to venv's own PYTHONHOME
        # handling and deactivate function. Each anchor is a whole line that
        # must occur exactly once, and the line before each insertion point is
        # checked as well, so a changed template fails creation rather than
        # producing a silently broken environment.
        if ! _cvmfs_venv_patch_activate "${_venv_python}" "${_activate}" \
            'unset _OLD_VIRTUAL_PYTHONHOME' 2 '    fi' "${_RECOVER_OLD_PYTHONPATH}" \
            'unset PYTHONHOME' 2 'fi' "${_SET_PYTHONPATH}" \
            'deactivate () {' 1 'deactivate () {' "${_RUN_REBASE}"$'\n' \
            'unset -f deactivate' 1 '        unset -f deactivate' "${_DESTRUCTIVE_UNSET}" \
            '# unset irrelevant variables' 0 '' "${_CVMFS_VENV_REBASE}"$'\n'; then
            echo "ERROR: Failed to add the cvmfs-venv hooks to '${_activate}'." >&2
            echo "       Removing the unusable environment '${_venv_name}'." >&2
            rm -rf "${_venv_name}"
            return 1
        fi
    fi

    # Activate the virtual environment
    # shellcheck source=/dev/null
    . "${_venv_name}/bin/activate"

    # Install uv by default
    if [ -z "${_no_uv}" ]; then
        # Ensure that uv is installed
        if ! command -v uv >/dev/null 2>&1; then
            echo "# Installing uv"
            # Check if pixi exists
            if command -v pixi >/dev/null 2>&1; then
                # Use pixi global
                echo "# Installing uv with pixi global"
                echo "# You can update uv with 'pixi global update uv'"
                pixi global install uv
            else
                # Install from https://astral.sh/
                echo "# Installing from https://astral.sh/"
                echo "# You can update uv with 'uv self update'"
                curl -LsSf https://astral.sh/uv/install.sh | sh
            fi

            # Ensure ~/.local/bin is on the PATH for uv
            if [[ ":${PATH}:" != *":${HOME}/.local/bin:"* ]]; then
                export PATH="${HOME}/.local/bin:${PATH}"
            fi
            # Enable uv shell autocompletion
            eval "$(uv generate-shell-completion bash)"
        fi
    fi

    # Get latest pip and setuptools
    if [ -z "${_no_update}" ]; then
        # Use uv by default
        if [ -z "${_no_uv}" ]; then
            uv pip --quiet install --upgrade pip setuptools
        else
            # Hide not-real errors from CVMFS by sending to /dev/null
            python -m pip --quiet --no-cache-dir install --upgrade pip setuptools &> /dev/null
        fi
    fi

    return 0
}

# Remove the functions from the shell (which may be an interactive shell that
# sourced this file) while preserving the exit status of _cvmfs_venv_main.
# A function may unset itself in bash; it still returns normally.
_cvmfs_venv_cleanup () {
    unset -f _cvmfs_venv_help _cvmfs_venv_patch_activate _cvmfs_venv_main _cvmfs_venv_cleanup
    return "${1}"
}

_cvmfs_venv_main "$@"
_cvmfs_venv_cleanup $?
