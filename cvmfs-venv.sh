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
 -s --setup     Shell command run first to set up the Python runtime, for
                example an lsetup or asetup command; setupATLAS is run
                before it when needed. Creation stops if the command's
                exit status (that of its last command, so join steps with
                '&&') is non-zero. In a Linux container that provides
                /release_setup.sh, that file is sourced instead.
 --no-system-site-packages
                The venv module '--system-site-packages' option is used by
                default. While it is not recommended, this behavior can be
                disabled through use of this flag.
 --no-update    After venv creation don't update pip and setuptools to the
                latest releases. Use of this option is not recommended,
                but is faster.
 --no-uv        Don't install uv, and use pip instead of uv to update pip
                and setuptools. By default, uv is installed if it is not
                found on PATH.

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

# _cvmfs_venv_ensure_uv
#
# Make a working uv available on PATH, installing it if needed, and return
# non-zero if that is not possible. Runs after activation; the directory
# holding uv is appended to PATH, so the environment's own bin stays first.
_cvmfs_venv_ensure_uv () {
    # Installer version, bumped deliberately. `uv self update` upgrades an
    # installed uv independently of this.
    local _uv_version="0.12.9"
    local _uv_dir="" _uv_found=""

    if command -v uv > /dev/null 2>&1; then
        uv --version > /dev/null 2>&1 && return 0
        echo "WARNING: The uv at '$(command -v uv)' does not work" >&2
        return 1
    fi

    # uv may already be installed but not on PATH in this shell. The
    # candidates follow the astral.sh installer's own order of precedence,
    # then the cargo and pixi directories.
    for _uv_dir in "${UV_UNMANAGED_INSTALL:-}" "${UV_INSTALL_DIR:-}" "${XDG_BIN_HOME:-}" "${XDG_DATA_HOME:+${XDG_DATA_HOME}/../bin}" "${HOME:-}/.local/bin" "${CARGO_HOME:-${HOME:-}/.cargo}/bin" "${PIXI_HOME:-${HOME:-}/.pixi}/bin"; do
        if [ -n "${_uv_dir}" ] && [ -x "${_uv_dir}/uv" ]; then
            _uv_found=true
            break
        fi
    done

    if [ -z "${_uv_found}" ]; then
        echo "# Installing uv"
        if command -v pixi > /dev/null 2>&1; then
            echo "# Installing uv with pixi global"
            echo "# You can update uv with 'pixi global update uv'"
            pixi global install uv || return 1
            _uv_dir="${PIXI_HOME:-${HOME:-}/.pixi}/bin"
        else
            echo "# Installing uv ${_uv_version} from https://astral.sh/"
            echo "# You can update uv with 'uv self update'"
            # The destination is chosen here, following the installer's own
            # precedence, and passed to it, so that where uv lands is known.
            _uv_dir="${UV_UNMANAGED_INSTALL:-${UV_INSTALL_DIR:-}}"
            [ -n "${_uv_dir}" ] || _uv_dir="${XDG_BIN_HOME:-}"
            [ -n "${_uv_dir}" ] || _uv_dir="${XDG_DATA_HOME:+${XDG_DATA_HOME}/../bin}"
            [ -n "${_uv_dir}" ] || _uv_dir="${HOME:-}/.local/bin"
            # The installer must not edit shell start-up files; PATH is
            # handled here. A failed or truncated download fails the pipeline,
            # and the installer only acts on its last line, so nothing partial
            # runs.
            if ! ( set -o pipefail; curl -LsSf --connect-timeout 10 --max-time 120 "https://astral.sh/uv/${_uv_version}/install.sh" | UV_INSTALL_DIR="${_uv_dir}" UV_NO_MODIFY_PATH=1 sh ); then
                return 1
            fi
            # A destination equal to CARGO_HOME gets the cargo layout
            if [ ! -x "${_uv_dir}/uv" ] && [ -x "${_uv_dir}/bin/uv" ]; then
                _uv_dir="${_uv_dir}/bin"
            fi
        fi
    fi

    if [ ! -x "${_uv_dir}/uv" ] || ! "${_uv_dir}/uv" --version > /dev/null 2>&1; then
        echo "WARNING: No working uv in '${_uv_dir}'" >&2
        return 1
    fi
    if [[ ":${PATH}:" != *":${_uv_dir}:"* ]]; then
        export PATH="${PATH}:${_uv_dir}"
        echo "# Add '${_uv_dir}' to PATH in your shell start-up file to use uv in new shells"
    fi
    # Shell completion is cosmetic and must not decide whether uv is usable
    eval "$(uv generate-shell-completion bash 2> /dev/null)" 2> /dev/null || true
    return 0
}

_cvmfs_venv_main () {
    local _setup_command=""
    local _no_system_site_packages=""
    local _no_update=""
    local _no_uv=""
    local _venv_name=""
    local _name_given=""
    local _activate_path=""
    local _venv_options=()
    local _venv_full_path=""
    local _marker="# Added by https://github.com/matthewfeickert/cvmfs-venv"
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
                if [ $# -lt 2 ] || [ -z "${2}" ]; then
                    echo "ERROR: '${1}' requires a non-empty argument" >&2
                    return 1
                fi
                if [ -n "${_setup_command}" ]; then
                    echo "ERROR: '${1}' may only be given once" >&2
                    return 1
                fi
                _setup_command="${2}"
                shift 2
                ;;
            -s=*|--setup=*)
                echo "ERROR: '${1%%=*}' takes its command as a separate argument: ${1%%=*} '<command>'" >&2
                return 1
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
                # Only the virtual environment name may follow
                shift
                if [ $# -gt 1 ]; then
                    echo "ERROR: Unexpected argument '${2}'" >&2
                    return 1
                fi
                if [ $# -eq 1 ]; then
                    if [ -n "${_name_given}" ]; then
                        echo "ERROR: Unexpected argument '${1}': virtual environment name already given as '${_venv_name}'" >&2
                        return 1
                    fi
                    if [ -z "${1}" ]; then
                        echo "ERROR: The virtual environment name may not be empty" >&2
                        return 1
                    fi
                    _venv_name="${1}"
                    _name_given=true
                fi
                break
                ;;
            -*)
                echo "ERROR: Invalid option '${1}'" >&2
                return 1
                ;;
            *)
                if [ -n "${_name_given}" ]; then
                    echo "ERROR: Unexpected argument '${1}': virtual environment name already given as '${_venv_name}'" >&2
                    return 1
                fi
                if [ -z "${1}" ]; then
                    echo "ERROR: The virtual environment name may not be empty" >&2
                    return 1
                fi
                _venv_name="${1}"
                _name_given=true
                shift
                ;;
        esac
    done
    _venv_name="${_venv_name:-venv}"

    if [ -n "${_setup_command}" ]; then
        if [ -f "/release_setup.sh" ]; then
            # If in Linux container
            if [[ "${_setup_command}" != *"/release_setup.sh"* ]]; then
                echo "WARNING: /release_setup.sh exists and it is assumed you are in a Linux container." >&2
                echo "         '${_setup_command}' will be skipped in favor of using '. /release_setup.sh'." >&2
            fi
            printf "\n. /release_setup.sh\n"
            # shellcheck source=/dev/null
            if ! . /release_setup.sh; then
                echo "ERROR: '. /release_setup.sh' failed" >&2
                return 1
            fi
        else
            # ATLAS commands need setupATLAS, which needs CVMFS. Match them as
            # words, so a file name such as my_lsetup_wrapper.sh does not count.
            if [[ "${_setup_command}" =~ (^|[^[:alnum:]_/.-])(lsetup|asetup)([^[:alnum:]_/.-]|$) ]]; then
                if [ ! -d "/cvmfs/atlas.cern.ch" ]; then
                    echo "ERROR: /cvmfs/atlas.cern.ch/ not found. Check that CernVM-FS is mounted correctly." >&2
                    return 1
                fi
                # Check to see if we need to run setupATLAS
                if ! command -v lsetup > /dev/null 2>&1; then
                    export ATLAS_LOCAL_ROOT_BASE=/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase
                    # Allows for working with wrappers as well. The exit status
                    # alone is not treated as fatal; what matters is whether
                    # lsetup is available afterwards.
                    # shellcheck source=/dev/null
                    . "${ATLAS_LOCAL_ROOT_BASE}/user/atlasLocalSetup.sh" -3 --quiet || echo "WARNING: setupATLAS returned a non-zero status" >&2
                    if ! command -v lsetup > /dev/null 2>&1; then
                        echo "ERROR: setupATLAS did not provide lsetup" >&2
                        return 1
                    fi
                fi
            fi

            printf '\n%s\n' "${_setup_command}"
            if ! eval -- "${_setup_command}"; then
                echo "ERROR: Setup command failed: ${_setup_command}" >&2
                return 1
            fi
        fi
    # If in Linux container
    elif [ -f "/release_setup.sh" ]; then
        echo "WARNING: /release_setup.sh exists and it is assumed you are in a Linux container." >&2
        echo "         Setting up environment with '. /release_setup.sh'." >&2
        printf "\n. /release_setup.sh\n"
        # shellcheck source=/dev/null
        if ! . /release_setup.sh; then
            echo "ERROR: '. /release_setup.sh' failed" >&2
            return 1
        fi
    fi

    if [ ! -e "${_venv_name}" ]; then
        if ! command -v python3 > /dev/null 2>&1; then
            echo "ERROR: python3 not found on PATH" >&2
            return 1
        fi
        printf "# Creating new Python virtual environment '%s'\n" "${_venv_name}"
        # Default to using --system-site-packages to add extra guards
        if [ -z "${_no_system_site_packages}" ]; then
            _venv_options=(--system-site-packages)
        fi
        # The guarded expansion keeps an empty array valid under set -u on
        # bash older than 4.4; `--` lets the name start with a dash.
        if ! python3 -m venv ${_venv_options[@]+"${_venv_options[@]}"} -- "${_venv_name}"; then
            echo "ERROR: Failed to create the virtual environment '${_venv_name}'." >&2
            if [ -d "${_venv_name}" ] && [ ! -L "${_venv_name}" ]; then
                echo "       Removing the partially created '${_venv_name}'." >&2
                rm -rf -- "${_venv_name}"
            fi
            return 1
        fi
        _venv_full_path="$(readlink -f -- "${_venv_name}")"
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
${_marker}
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
    ${_marker}
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
    ${_marker}
    cvmfs-venv-rebase  # Keep lsetup PATHs added while venv active
EOT
)

        # If the deactivate is being run in a destructive manner (i.e., anytime that isn't
        # the sanitizing pass through on activate) then unset cvmfs-venv-rebase.
        _DESTRUCTIVE_UNSET=$(cat <<EOT
        ${_marker}
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
${_marker}
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
            rm -rf -- "${_venv_name}"
            return 1
        fi
    elif [ -r "${_venv_name}/bin/activate" ] && grep -qF -- "${_marker}" "${_venv_name}/bin/activate"; then
        : # Created by cvmfs-venv earlier, so only activation is needed
    elif [ -r "${_venv_name}/bin/activate" ]; then
        echo "ERROR: '${_venv_name}' is a Python virtual environment that was not created by cvmfs-venv." >&2
        echo "       Choose another name, or remove it to have cvmfs-venv create it." >&2
        return 1
    elif [ -e "${_venv_name}/pyvenv.cfg" ] || [ -e "${_venv_name}/bin/activate" ]; then
        echo "ERROR: '${_venv_name}' is an incomplete or unreadable virtual environment: bin/activate is missing or cannot be read." >&2
        echo "       Remove it, or fix its permissions, before trying again." >&2
        return 1
    else
        echo "ERROR: '${_venv_name}' exists and is not a Python virtual environment." >&2
        return 1
    fi

    # Activate the virtual environment. The dot builtin would read a leading
    # dash as an option, so make such a path explicitly relative. Success is
    # judged by the outcome as well as by the status.
    _activate_path="${_venv_name}/bin/activate"
    case "${_activate_path}" in -*) _activate_path="./${_activate_path}" ;; esac
    # shellcheck source=/dev/null
    if ! . "${_activate_path}" || [ ! "${VIRTUAL_ENV:-}/bin/activate" -ef "${_activate_path}" ]; then
        echo "ERROR: Failed to activate '${_venv_name}' (the shell may have been partly modified)" >&2
        return 1
    fi

    # Ensure that pip can't install outside a virtual environment
    export PIP_REQUIRE_VIRTUALENV=true

    # Use uv by default, installing it if needed. This runs after activation
    # and appends to PATH, so the environment's own bin stays first, and a uv
    # that only lived in a previously active environment cannot be mistaken
    # for one that stays available.
    if [ -z "${_no_uv}" ] && ! _cvmfs_venv_ensure_uv; then
        echo "WARNING: uv is not available; continuing without it." >&2
        _no_uv=true
    fi

    # Get latest pip and setuptools
    if [ -z "${_no_update}" ]; then
        if [ -z "${_no_uv}" ] && ! uv pip --quiet install --python "${VIRTUAL_ENV}" --upgrade pip setuptools; then
            echo "WARNING: uv failed to update pip and setuptools, so pip will be used instead." >&2
            _no_uv=true
        fi
        if [ -n "${_no_uv}" ]; then
            # pip on CVMFS prints errors that are not real, so only the exit
            # status is reported.
            if ! python -m pip --quiet --no-cache-dir install --upgrade pip setuptools > /dev/null 2>&1; then
                echo "WARNING: Failed to update pip and setuptools with pip" >&2
            fi
        fi
    fi

    return 0
}

# Remove the functions from the shell (which may be an interactive shell that
# sourced this file) while preserving the exit status of _cvmfs_venv_main.
# A function may unset itself in bash; it still returns normally.
_cvmfs_venv_cleanup () {
    unset -f _cvmfs_venv_help _cvmfs_venv_patch_activate _cvmfs_venv_ensure_uv _cvmfs_venv_main _cvmfs_venv_cleanup
    return "${1}"
}

_cvmfs_venv_main "$@"
_cvmfs_venv_cleanup $?
