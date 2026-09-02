#!/bin/bash
#
# Behavioural tests for cvmfs-venv.sh.
#
# Invocations pass --no-uv --no-update, or stub the commands the uv step would
# run, so the tests need no network access and never install anything. Each
# case runs in a fresh subshell and working directory; a case passes when its
# snippet exits 0.
#
#     tests/test_cvmfs_venv.sh [python3 executable]
#
# The exit status is non-zero if any case fails.

# Test bodies are single-quoted on purpose: they are expanded by the subshell that runs them.
# shellcheck disable=SC2016
set -u

_tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CVMFS_VENV="${CVMFS_VENV:-${_tests_dir}/../cvmfs-venv.sh}"
_python3="$(command -v "${1:-python3}")" || { echo "ERROR: python3 not found" >&2; exit 2; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "${SANDBOX}"' EXIT

# Make the requested interpreter the python3 that cvmfs-venv will use. A
# wrapper that execs the interpreter (rather than a symlink) keeps
# sys.executable pointing at the real installation, which venv needs in
# order to record a usable home directory. No case uses pip, so venv creation
# skips ensurepip, which otherwise dominates the run time.
mkdir -p "${SANDBOX}/bin"
cat > "${SANDBOX}/bin/python3" <<EOF
#!/bin/bash
if [ "\${1:-}" = -m ] && [ "\${2:-}" = venv ]; then
    shift 2
    set -- -m venv --without-pip "\$@"
fi
exec "${_python3}" "\$@"
EOF
chmod +x "${SANDBOX}/bin/python3"
export PATH="${SANDBOX}/bin:${PATH}"
# The suite may be run from an activated environment or a shell that
# configures uv, pixi or XDG directories; cases start without any of that.
unset VIRTUAL_ENV _OLD_VIRTUAL_PATH _OLD_VIRTUAL_PYTHONPATH _VIRTUAL_SITE_PACKAGES PIP_REQUIRE_VIRTUALENV
unset UV_UNMANAGED_INSTALL UV_INSTALL_DIR XDG_BIN_HOME XDG_DATA_HOME CARGO_HOME PIXI_HOME UV_STUB_LOG UV_STUB_BROKEN UV_STUB_FAIL_PIP
# Standing guard: nothing in the suite may reach a package index
export PIP_NO_INDEX=1 UV_OFFLINE=1

# check <command...>: run the command and exit the case with a message if it fails.
check () {
    if ! "$@"; then
        echo "check failed: $*" >&2
        exit 1
    fi
}
export -f check

_passed=0
_failed=0

# run_case <name> <bash snippet>
run_case () {
    local _name="${1}" _body="${2}" _workdir _output _status
    _workdir="$(mktemp -d "${SANDBOX}/case.XXXXXX")"
    _output="$(cd "${_workdir}" && timeout 120 bash -c "${_body}" 2>&1)"
    _status=$?
    if [ "${_status}" -eq 0 ]; then
        _passed=$((_passed + 1))
        echo "ok - ${_name}"
    else
        _failed=$((_failed + 1))
        echo "not ok - ${_name} (exit status ${_status})"
        printf '%s\n' "${_output}" | sed 's/^/    # /'
    fi
}

echo "# cvmfs-venv tests with $("${_python3}" --version 2>&1) at ${_python3}"

run_case "help prints usage and returns 0 when executed" '
    _usage="$("${CVMFS_VENV}" --help)"
    check [ $? -eq 0 ]
    check grep -q "^Usage: cvmfs-venv" <<< "${_usage}"
'

run_case "help returns 0 when sourced" '
    . "${CVMFS_VENV}" --help > /dev/null
    check [ $? -eq 0 ]
'

run_case "invalid option returns 1 when executed" '
    "${CVMFS_VENV}" --bogus 2> /dev/null
    check [ $? -eq 1 ]
'

run_case "invalid option returns 1 when sourced and the shell survives" '
    . "${CVMFS_VENV}" --bogus 2> /dev/null
    _status=$?
    # If the sourced script had called exit, this line is never reached.
    check [ "${_status}" -eq 1 ]
    exit 0
'

run_case "missing CVMFS with an ATLAS setup command returns 1 when sourced and the shell survives" '
    if [ -d /cvmfs/atlas.cern.ch ] || [ -f /release_setup.sh ]; then
        echo "skipped: /cvmfs/atlas.cern.ch is mounted or /release_setup.sh exists"
        exit 0
    fi
    . "${CVMFS_VENV}" --no-uv --no-update --setup "lsetup views" nocvmfs 2> /dev/null
    _status=$?
    check [ "${_status}" -eq 1 ]
    check [ ! -d nocvmfs ]
    exit 0
'

run_case "--setup without an argument returns 1 instead of looping" '
    # A regression here loops forever, so the sourced call gets its own
    # timeout; "returned-1" is only printed when the script returned rather
    # than exited.
    _output="$(timeout 10 bash -c ". \"${CVMFS_VENV}\" --setup 2> /dev/null; _status=\$?; [ \"\${_status}\" -eq 1 ] && echo returned-1")"
    check grep -q "^returned-1$" <<< "${_output}"
    "${CVMFS_VENV}" -s 2> /dev/null
    check [ $? -eq 1 ]
'

run_case "an empty, repeated, or joined --setup is rejected" '
    for _args in "--setup \"\"" "--setup true --setup true" "--setup=true" "-s=true"; do
        eval "set -- ${_args}"
        _output="$("${CVMFS_VENV}" --no-uv --no-update "$@" tv 2>&1)"
        check [ $? -eq 1 ]
        check grep -q "^ERROR: " <<< "${_output}"
        check [ ! -e tv ]
    done
    _output="$("${CVMFS_VENV}" --no-uv --no-update --setup=true tv 2>&1)"
    check grep -q "separate argument" <<< "${_output}"
'

run_case "the environment name may come before options" '
    . "${CVMFS_VENV}" tv --no-uv --no-update > /dev/null
    check [ "${VIRTUAL_ENV:-}" = "${PWD}/tv" ]
'

run_case "a second positional argument is an error" '
    for _args in "tv extra" "-- tv extra" "tv -- other"; do
        eval "set -- ${_args}"
        _output="$("${CVMFS_VENV}" --no-uv --no-update "$@" 2>&1)"
        check [ $? -eq 1 ]
        check grep -q "^ERROR: Unexpected argument" <<< "${_output}"
        check [ ! -e tv ]
    done
'

run_case "an empty name is rejected" '
    for _args in "\"\"" "\"\" second" "-- \"\""; do
        eval "set -- ${_args}"
        _output="$("${CVMFS_VENV}" --no-uv --no-update "$@" 2>&1)"
        check [ $? -eq 1 ]
        check grep -q "may not be empty" <<< "${_output}"
    done
    check [ ! -e venv ]
    check [ ! -e second ]
'

run_case "a name may contain -- but may only start with - after --" '
    "${CVMFS_VENV}" --no-uv --no-update my--venv > /dev/null
    check [ $? -eq 0 ]
    check [ -f my--venv/pyvenv.cfg ]
    "${CVMFS_VENV}" --no-uv --no-update -venv 2> /dev/null
    check [ $? -eq 1 ]
    check [ ! -e ./-venv ]
    . "${CVMFS_VENV}" --no-uv --no-update -- -venv > /dev/null
    check [ $? -eq 0 ]
    check [ "${VIRTUAL_ENV:-}" = "${PWD}/-venv" ]
    check [ "$(command -v python)" = "${PWD}/-venv/bin/python" ]
'

run_case "a setup command is run in the calling shell before creation" '
    if [ -f /release_setup.sh ]; then echo "skipped: /release_setup.sh exists"; exit 0; fi
    . "${CVMFS_VENV}" --no-uv --no-update --setup "export CVMFS_VENV_TEST_MARK=set" tv > /dev/null
    check [ $? -eq 0 ]
    check [ "${CVMFS_VENV_TEST_MARK:-}" = set ]
    check [ "${VIRTUAL_ENV:-}" = "${PWD}/tv" ]
'

run_case "a failing setup command returns 1 and creates nothing" '
    if [ -f /release_setup.sh ]; then echo "skipped: /release_setup.sh exists"; exit 0; fi
    . "${CVMFS_VENV}" --no-uv --no-update --setup "false" tv 2> /dev/null
    check [ $? -eq 1 ]
    check [ ! -e tv ]
    check [ -z "${VIRTUAL_ENV:-}" ]
    # The status is that of the last command in the string, as documented
    "${CVMFS_VENV}" --no-uv --no-update --setup "true && false" tv 2> /dev/null
    check [ $? -eq 1 ]
    check [ ! -e tv ]
    # A setup string starting with a dash is reported as a failed command
    _output="$("${CVMFS_VENV}" --no-uv --no-update -s --no-uv tv 2>&1)"
    check [ $? -eq 1 ]
    check grep -q "^ERROR: Setup command failed: --no-uv" <<< "${_output}"
'

run_case "lsetup inside a file name does not make the setup command an ATLAS one" '
    if [ -d /cvmfs/atlas.cern.ch ] || [ -f /release_setup.sh ]; then echo "skipped: CVMFS or /release_setup.sh present"; exit 0; fi
    printf "export CVMFS_VENV_WRAPPER_RAN=yes\n" > my_lsetup_wrapper.sh
    . "${CVMFS_VENV}" --no-uv --no-update --setup "source ./my_lsetup_wrapper.sh" tv > /dev/null
    check [ $? -eq 0 ]
    check [ "${CVMFS_VENV_WRAPPER_RAN:-}" = yes ]
    check [ "${VIRTUAL_ENV:-}" = "${PWD}/tv" ]
'

run_case "a failed venv creation returns 1 and never reaches the uv step" '
    if [ -f /release_setup.sh ]; then echo "skipped: /release_setup.sh puts a real python3 ahead of the stub"; exit 0; fi
    mkdir shims
    printf "%s\n" "#!/bin/sh" "touch \"${PWD}/uv-called\"" "exit 0" > shims/uv
    printf "%s\n" "#!/bin/sh" "exit 1" > shims/python3
    chmod +x shims/uv shims/python3
    export PATH="${PWD}/shims:${PATH}"
    _output="$(. "${CVMFS_VENV}" tv 2>&1)"
    check [ $? -eq 1 ]
    check grep -q "^ERROR: Failed to create the virtual environment" <<< "${_output}"
    check [ ! -e uv-called ]
    check [ ! -e tv ]
    check [ -z "${VIRTUAL_ENV:-}" ]
    check [ -z "${PIP_REQUIRE_VIRTUALENV:-}" ]
'

run_case "a partially created environment is removed after a failed creation" '
    # Wrap python3 so that venv writes pyvenv.cfg and bin/python but then fails
    mkdir wrap
    cat > wrap/python3 <<EOF
#!/bin/bash
"$(command -v python3)" "\$@"; _status=\$?
if [ "\${1:-}" = -m ] && [ "\${2:-}" = venv ]; then rm -f "\${!#}/bin/activate"; exit 1; fi
exit \${_status}
EOF
    chmod +x wrap/python3
    export PATH="${PWD}/wrap:${PATH}"
    _output="$("${CVMFS_VENV}" --no-uv --no-update tv 2>&1)"
    check [ $? -eq 1 ]
    check grep -q "Removing the partially created" <<< "${_output}"
    check [ ! -e tv ]
'

run_case "python3 missing from PATH is reported" '
    _output="$(bash -c "export PATH=/nonexistent; . \"${CVMFS_VENV}\" --no-uv --no-update tv" 2>&1)"
    check [ $? -eq 1 ]
    check grep -q "^ERROR: python3 not found on PATH" <<< "${_output}"
'

run_case "an existing directory or file that is not a venv is refused" '
    mkdir notavenv
    touch afile
    for _name in notavenv afile; do
        _output="$(. "${CVMFS_VENV}" --no-uv --no-update "${_name}" 2>&1)"
        check [ $? -eq 1 ]
        check grep -q "is not a Python virtual environment" <<< "${_output}"
    done
    . "${CVMFS_VENV}" --no-uv --no-update notavenv 2> /dev/null
    check [ -z "${VIRTUAL_ENV:-}" ]
    # A refused run must not leave the pip guard behind in the shell
    check [ -z "${PIP_REQUIRE_VIRTUALENV:-}" ]
'

run_case "an incomplete or unreadable environment is reported as such" '
    # pyvenv.cfg without bin/activate, as a failed creation could leave behind
    "${CVMFS_VENV}" --no-uv --no-update tv > /dev/null
    rm tv/bin/activate
    _output="$(. "${CVMFS_VENV}" --no-uv --no-update tv 2>&1)"
    check [ $? -eq 1 ]
    check grep -q "incomplete or unreadable" <<< "${_output}"
    if [ "$(id -u)" -eq 0 ]; then echo "skipped unreadable check: running as root"; exit 0; fi
    "${CVMFS_VENV}" --no-uv --no-update tv2 > /dev/null
    chmod 000 tv2/bin/activate
    _output="$(. "${CVMFS_VENV}" --no-uv --no-update tv2 2>&1)"
    check [ $? -eq 1 ]
    check grep -q "incomplete or unreadable" <<< "${_output}"
'

run_case "an activate that fails or does not activate is reported" '
    "${CVMFS_VENV}" --no-uv --no-update tv > /dev/null
    _marker="$(grep -m1 "Added by https://github.com/matthewfeickert/cvmfs-venv" tv/bin/activate)"
    # Keeps the marker but never sets VIRTUAL_ENV
    printf "%s\n" "${_marker}" > tv/bin/activate
    _output="$(. "${CVMFS_VENV}" --no-uv --no-update tv 2>&1)"
    check [ $? -eq 1 ]
    check grep -q "^ERROR: Failed to activate" <<< "${_output}"
    "${CVMFS_VENV}" --no-uv --no-update tv2 > /dev/null
    echo false >> tv2/bin/activate
    _output="$(. "${CVMFS_VENV}" --no-uv --no-update tv2 2>&1)"
    check [ $? -eq 1 ]
    check grep -q "^ERROR: Failed to activate" <<< "${_output}"
'

run_case "an existing venv without the cvmfs-venv hooks is refused" '
    python3 -m venv --without-pip plain
    _output="$(. "${CVMFS_VENV}" --no-uv --no-update plain 2>&1)"
    check [ $? -eq 1 ]
    check grep -q "not created by cvmfs-venv" <<< "${_output}"
'

run_case "help and errors leave no functions or variables behind when sourced" '
    _before="$(compgen -v; compgen -A function)"
    . "${CVMFS_VENV}" --help > /dev/null
    . "${CVMFS_VENV}" --bogus 2> /dev/null
    _after="$(compgen -v; compgen -A function)"
    _new="$(comm -13 <(echo "${_before}" | sort) <(echo "${_after}" | sort) | grep -vx -e _before -e _after -e PIPESTATUS)"
    check [ -z "${_new}" ]
'

run_case "creating a venv injects the activate hooks" '
    . "${CVMFS_VENV}" --no-uv --no-update tv
    check [ $? -eq 0 ]
    check [ -f tv/pyvenv.cfg ]
    check [ "${VIRTUAL_ENV}" = "${PWD}/tv" ]
    check [ "$(command -v python)" = "${PWD}/tv/bin/python" ]
    check [ "${PIP_REQUIRE_VIRTUALENV:-}" = true ]
    check bash -n tv/bin/activate
    check grep -q "^cvmfs-venv-rebase () {" tv/bin/activate
    check [ "$(grep -c "Added by https://github.com/matthewfeickert/cvmfs-venv" tv/bin/activate)" -eq 5 ]
'

run_case "activating with PYTHONPATH set prepends site-packages and deactivate restores it exactly" '
    "${CVMFS_VENV}" --no-uv --no-update tv > /dev/null
    export PYTHONPATH=/fake/lcg:/another/lcg
    . tv/bin/activate
    check [ "${VIRTUAL_ENV:-}" = "${PWD}/tv" ]
    _site_packages="$(python -c "import sysconfig; print(sysconfig.get_paths()[\"purelib\"])")"
    check [ -d "${_site_packages}" ]
    check [ "${PYTHONPATH}" = "${_site_packages}:/fake/lcg:/another/lcg" ]
    deactivate
    check [ "${PYTHONPATH}" = "/fake/lcg:/another/lcg" ]
    check [ -z "${_OLD_VIRTUAL_PYTHONPATH:-}" ]
    check [ -z "${_VIRTUAL_SITE_PACKAGES:-}" ]
    check [ -z "${VIRTUAL_ENV:-}" ]
    check [ -z "$(type -t cvmfs-venv-rebase)" ]
'

run_case "deactivate keeps PATH and PYTHONPATH additions made while active" '
    "${CVMFS_VENV}" --no-uv --no-update tv > /dev/null
    export PYTHONPATH=/fake/lcg
    . tv/bin/activate
    check [ "${VIRTUAL_ENV:-}" = "${PWD}/tv" ]
    export PATH="/added/bin:${PATH}"
    export PYTHONPATH="/added/lib:${PYTHONPATH}"
    deactivate
    check [ "${PATH%%:*}" = /added/bin ]
    case ":${PATH}:" in *":${PWD}/tv/bin:"*) echo "venv bin still on PATH"; exit 1 ;; esac
    check [ "${PYTHONPATH}" = "/added/lib:/fake/lcg" ]
'

run_case "sourcing a venv creation leaves only the expected state behind" '
    if [ -f /release_setup.sh ]; then echo "skipped: /release_setup.sh is sourced in a container"; exit 0; fi
    _before="$(compgen -v; compgen -A function)"
    . "${CVMFS_VENV}" --no-uv --no-update tv
    deactivate
    _after="$(compgen -v; compgen -A function)"
    # A stock venv activate/deactivate cycle itself leaves _OLD_VIRTUAL_PS1 and PS1.
    _new="$(comm -13 <(echo "${_before}" | sort) <(echo "${_after}" | sort) \
        | grep -vx -e _before -e _after -e PIPESTATUS -e _OLD_VIRTUAL_PS1 -e PS1 -e PIP_REQUIRE_VIRTUALENV)"
    if [ -n "${_new}" ]; then echo "leaked: ${_new}"; exit 1; fi
'

run_case "a successful sourced run works under set -e and set -u" '
    set -e
    # A container setup script sourced by cvmfs-venv need not be set -u safe
    [ -f /release_setup.sh ] || set -u
    . "${CVMFS_VENV}" --no-uv --no-update tv
    check [ -n "${VIRTUAL_ENV}" ]
'

run_case "a venv name containing a space gets all hooks and a correct PYTHONPATH" '
    "${CVMFS_VENV}" --no-uv --no-update "my venv" > /dev/null
    check [ $? -eq 0 ]
    check [ "$(grep -c "Added by https://github.com/matthewfeickert/cvmfs-venv" "my venv/bin/activate")" -eq 5 ]
    export PYTHONPATH=/fake/lcg
    . "my venv/bin/activate"
    check [ "${VIRTUAL_ENV:-}" = "${PWD}/my venv" ]
    _site_packages="$(python -c "import sysconfig; print(sysconfig.get_paths()[\"purelib\"])")"
    check [ "${PYTHONPATH}" = "${_site_packages}:/fake/lcg" ]
    export PATH="/added/bin:${PATH}"
    deactivate
    check [ "${PYTHONPATH}" = /fake/lcg ]
    check [ "${PATH%%:*}" = /added/bin ]
    case ":${PATH}:" in *":${PWD}/my venv/bin:"*) echo "venv bin still on PATH"; exit 1 ;; esac
'

run_case "a venv below a directory containing a space gets a correct PYTHONPATH" '
    mkdir "dir with space" && cd "dir with space"
    "${CVMFS_VENV}" --no-uv --no-update tv > /dev/null
    export PYTHONPATH=/fake/lcg
    . tv/bin/activate
    check [ "${VIRTUAL_ENV:-}" = "${PWD}/tv" ]
    # An empty PYTHONPATH element would put the working directory on sys.path.
    case "${PYTHONPATH}" in :*|*::*|*:) echo "empty PYTHONPATH element: ${PYTHONPATH}"; exit 1 ;; esac
    _site_packages="$(python -c "import sysconfig; print(sysconfig.get_paths()[\"purelib\"])")"
    check [ "${PYTHONPATH}" = "${_site_packages}:/fake/lcg" ]
    deactivate
    check [ "${PYTHONPATH}" = /fake/lcg ]
'

run_case "activate bakes in the site-packages path and does no filesystem search" '
    "${CVMFS_VENV}" --no-uv --no-update tv > /dev/null
    _relative="$(tv/bin/python -c "import os, sys, sysconfig; print(os.path.relpath(sysconfig.get_paths()[\"purelib\"], sys.prefix))")"
    check [ -d "tv/${_relative}" ]
    check grep -qF "    _VIRTUAL_SITE_PACKAGES=\"\${VIRTUAL_ENV}/${_relative}\"" tv/bin/activate
    if grep -E "_VIRTUAL_SITE_PACKAGES=.*(\\$\\(|\`)" tv/bin/activate; then echo "site-packages is computed at activation"; exit 1; fi
    # Lines that cvmfs-venv added (those not in a stock activate) must be clean
    python3 -m venv stock
    if comm -13 <(sort stock/bin/activate) <(sort tv/bin/activate) | grep -nE "[[:space:]]+$"; then
        echo "added lines have trailing whitespace"; exit 1
    fi
'

run_case "no editor or search tool is needed to add the hooks" '
    mkdir shims
    for _tool in ed vi sed find mktemp; do
        printf "#!/bin/sh\necho \"%s must not be used\" >&2\nexit 99\n" "${_tool}" > "shims/${_tool}"
        chmod +x "shims/${_tool}"
    done
    export PATH="${PWD}/shims:${PATH}"
    "${CVMFS_VENV}" --no-uv --no-update tv > /dev/null
    check [ $? -eq 0 ]
    check [ "$(grep -c "Added by https://github.com/matthewfeickert/cvmfs-venv" tv/bin/activate)" -eq 5 ]
'

run_case "start-up output from the interpreter does not corrupt the baked path" '
    # Wrap python3 so that the venv it creates has a .pth file that prints,
    # as site-packages on CVMFS may.
    mkdir wrap
    cat > wrap/python3 <<EOF
#!/bin/bash
"$(command -v python3)" "\$@"; _status=\$?
if [ "\${1:-}" = -m ] && [ "\${2:-}" = venv ]; then
    echo "import sys; sys.stdout.write(\"compat layer loaded\\n\")" > "\${!#}"/lib/python*/site-packages/zz_noisy.pth
fi
exit \${_status}
EOF
    chmod +x wrap/python3
    export PATH="${PWD}/wrap:${PATH}"
    "${CVMFS_VENV}" --no-uv --no-update tv > /dev/null
    check [ $? -eq 0 ]
    export PYTHONPATH=/fake/lcg
    . tv/bin/activate
    check [ "${VIRTUAL_ENV:-}" = "${PWD}/tv" ]
    check [ -d "${PYTHONPATH%%:*}" ]
    check [ "${PYTHONPATH}" = "$(python -c "import sysconfig; print(sysconfig.get_paths()[\"purelib\"])" | tail -n 1):/fake/lcg" ]
'

run_case "a venv path with glob characters is removed from PATH and PYTHONPATH on deactivate" '
    "${CVMFS_VENV}" --no-uv --no-update "v[1]" > /dev/null
    export PYTHONPATH=/fake/lcg
    . "v[1]/bin/activate"
    check [ "${VIRTUAL_ENV:-}" = "${PWD}/v[1]" ]
    export PATH="/added/bin:${PATH}"
    export PYTHONPATH="/added/lib:${PYTHONPATH}"
    deactivate
    check [ "${PATH%%:*}" = /added/bin ]
    case ":${PATH}:" in *":${PWD}/v[1]/bin:"*) echo "venv bin still on PATH"; exit 1 ;; esac
    check [ "${PYTHONPATH}" = "/added/lib:/fake/lcg" ]
'

run_case "clearing PYTHONPATH while active does not leak site-packages on deactivate" '
    "${CVMFS_VENV}" --no-uv --no-update tv > /dev/null
    # The generated activate, deactivate and rebase must all be set -u safe
    set -eu
    export PYTHONPATH=/fake/lcg
    . tv/bin/activate
    check [ "${VIRTUAL_ENV:-}" = "${PWD}/tv" ]
    unset PYTHONPATH
    deactivate
    check [ "${PYTHONPATH:-}" = /fake/lcg ]
    check [ -z "${_VIRTUAL_SITE_PACKAGES:-}" ]
    check [ -z "${_OLD_VIRTUAL_PYTHONPATH:-}" ]
    # Only the site-packages left on PYTHONPATH: deactivate empties it
    . tv/bin/activate
    export PYTHONPATH="${_VIRTUAL_SITE_PACKAGES}"
    deactivate
    check [ -z "${PYTHONPATH:-}" ]
    check [ -z "${_VIRTUAL_SITE_PACKAGES:-}" ]
'

run_case "an unrecognised activate template fails loudly and leaves nothing behind" '
    # Wrap python3 so that the venv it creates has its activate mutated with
    # the sed expression in MUTATION (GNU sed -i; the suite is Linux-only).
    mkdir wrap
    cat > wrap/python3 <<EOF
#!/bin/bash
"$(command -v python3)" "\$@"; _status=\$?
if [ "\${1:-}" = -m ] && [ "\${2:-}" = venv ]; then sed -i "\${MUTATION}" "\${!#}/bin/activate"; fi
exit \${_status}
EOF
    chmod +x wrap/python3
    export PATH="${PWD}/wrap:${PATH}"
    _mutations=(
        "s/^deactivate () {/deactivate() {/"      # anchor missing
        "s/^    unset PYTHONHOME$/&\n    unset PYTHONHOME/"  # anchor duplicated
        "s/^    unset PYTHONHOME$/&\n    : extra line/"      # block longer than expected
    )
    for MUTATION in "${_mutations[@]}"; do
        export MUTATION
        _output="$("${CVMFS_VENV}" --no-uv --no-update tv 2>&1)"
        _status=$?
        check [ "${_status}" -eq 1 ]
        check grep -q "^ERROR: expected" <<< "${_output}"
        check grep -q "^ERROR: Failed to add the cvmfs-venv hooks" <<< "${_output}"
        check [ ! -e tv ]
    done
'

run_case "a double dash ends option parsing" '
    . "${CVMFS_VENV}" --no-uv --no-update -- tv > /dev/null
    check [ "${VIRTUAL_ENV}" = "${PWD}/tv" ]
'

run_case "an existing cvmfs-venv is activated without being recreated" '
    "${CVMFS_VENV}" --no-uv --no-update tv > /dev/null
    _mtime="$(stat -c %Y tv/bin/activate)"
    . "${CVMFS_VENV}" --no-uv --no-update tv > /dev/null
    check [ $? -eq 0 ]
    check [ "${VIRTUAL_ENV}" = "${PWD}/tv" ]
    check [ "$(stat -c %Y tv/bin/activate)" = "${_mtime}" ]
'

# The uv cases stub pixi, curl and uv so nothing is downloaded. The uv stub
# answers --version and the completion query and records everything else in
# UV_STUB_LOG; UV_STUB_BROKEN=1 makes --version fail and UV_STUB_FAIL_PIP=1
# makes pip subcommands fail.
make_uv_stub () {
    mkdir -p "$(dirname "${1}")"
    cat > "${1}" <<'STUB'
#!/bin/sh
case "${1:-}" in
    --version)
        [ "${UV_STUB_BROKEN:-}" != 1 ] || exit 1
        echo "uv 0.0.0 (stub)"
        ;;
    generate-shell-completion)
        printf '%s\n' '_uv_stub_complete () { :; }' 'complete -F _uv_stub_complete uv'
        ;;
    *)
        echo "$*" >> "${UV_STUB_LOG}"
        [ "${UV_STUB_FAIL_PIP:-}" != 1 ] || [ "${1:-}" != pip ] || exit 1
        ;;
esac
STUB
    chmod +x "${1}"
}
export -f make_uv_stub

# uv_free_path: a PATH holding only the interpreter under test and the system
# directories, with neither uv nor pixi on it, so that each case controls both.
uv_free_path () {
    PATH="$(dirname "$(command -v python3)"):/usr/bin:/bin"
    export PATH
    if command -v uv > /dev/null 2>&1 || command -v pixi > /dev/null 2>&1; then
        echo "skipped: uv or pixi is installed in a system directory"
        exit 0
    fi
}
export -f uv_free_path

# make_fake_installer <path>: a stand-in for the astral.sh installer, run with
# sh like the real one. It installs the uv stub where the real installer
# would, records its environment, and edits ~/.bashrc unless told not to.
make_fake_installer () {
    cat > "${1}" <<'INSTALLER'
#!/bin/sh
env > "${HOME}/installer.env"
dir="${UV_UNMANAGED_INSTALL:-${UV_INSTALL_DIR:-}}"
[ -n "${dir}" ] || dir="${XDG_BIN_HOME:-}"
[ -n "${dir}" ] || dir="${XDG_DATA_HOME:+${XDG_DATA_HOME}/../bin}"
[ -n "${dir}" ] || dir="${HOME}/.local/bin"
mkdir -p "${dir}"
cp "${UV_STUB_SOURCE}" "${dir}/uv"
[ "${UV_NO_MODIFY_PATH:-0}" = 1 ] || echo "export PATH=\"${dir}:\$PATH\"" >> "${HOME}/.bashrc"
INSTALLER
    chmod +x "${1}"
}
export -f make_fake_installer

run_case "a working uv on PATH is used for the update and nothing is installed" '
    export UV_STUB_LOG="${PWD}/uv.log" HOME="${PWD}/home"
    mkdir home
    uv_free_path
    make_uv_stub "${PWD}/shims/uv"
    printf "%s\n" "#!/bin/sh" "touch \"${PWD}/curl-called\"" "exit 1" > shims/curl
    chmod +x shims/curl
    export PATH="${PWD}/shims:${PATH}"
    . "${CVMFS_VENV}" tv > /dev/null
    check [ $? -eq 0 ]
    check [ "${PATH%%:*}" = "${PWD}/tv/bin" ]
    check [ "$(command -v uv)" = "${PWD}/shims/uv" ]
    check [ ! -e curl-called ]
    check [ ! -e home/.local ]
    check grep -qxF "pip --quiet install --python ${PWD}/tv --upgrade pip setuptools" uv.log
'

run_case "uv installed with pixi lands behind the venv on PATH, with the PATH hint" '
    export UV_STUB_LOG="${PWD}/uv.log" HOME="${PWD}/home"
    mkdir home shims
    uv_free_path
    printf "#!/bin/bash\n[ \"\$1 \$2 \$3\" = \"global install uv\" ] || exit 1\nmake_uv_stub \"\${HOME}/.pixi/bin/uv\"\n" > shims/pixi
    chmod +x shims/pixi
    export PATH="${PWD}/shims:${PATH}"
    _output="$(. "${CVMFS_VENV}" tv; echo "status=$?"; echo "path-head=${PATH%%:*}"; echo "path-tail=${PATH##*:}"; echo "uv=$(command -v uv)")"
    check grep -qxF "status=0" <<< "${_output}"
    check grep -qxF "path-head=${PWD}/tv/bin" <<< "${_output}"
    check grep -qxF "path-tail=${HOME}/.pixi/bin" <<< "${_output}"
    check grep -qxF "uv=${HOME}/.pixi/bin/uv" <<< "${_output}"
    check grep -qF "# Add '\''${HOME}/.pixi/bin'\'' to PATH" <<< "${_output}"
    check grep -qxF "pip --quiet install --python ${PWD}/tv --upgrade pip setuptools" uv.log
'

run_case "uv installed from astral.sh honours the XDG directories and edits no start-up file" '
    export UV_STUB_LOG="${PWD}/uv.log" HOME="${PWD}/home" XDG_DATA_HOME="${PWD}/home/share"
    mkdir -p home/share shims
    uv_free_path
    make_uv_stub "${PWD}/uv-stub"
    export UV_STUB_SOURCE="${PWD}/uv-stub"
    make_fake_installer "${PWD}/fake-installer.sh"
    # The script pipes the download into sh: the stub records the arguments
    # and prints the fake installer
    printf "%s\n" "#!/bin/bash" "printf \"%s\\\\n\" \"\$@\" > \"${PWD}/curl.args\"" "cat \"${PWD}/fake-installer.sh\"" > shims/curl
    chmod +x shims/curl
    export PATH="${PWD}/shims:${PATH}"
    . "${CVMFS_VENV}" tv > /dev/null
    check [ $? -eq 0 ]
    check grep -qxF -- "https://astral.sh/uv/0.12.9/install.sh" curl.args
    check grep -qxF -- "--connect-timeout" curl.args
    check grep -qxF "UV_NO_MODIFY_PATH=1" home/installer.env
    check grep -qxF "UV_INSTALL_DIR=${XDG_DATA_HOME}/../bin" home/installer.env
    check [ ! -e home/.bashrc ]
    check [ ! -e home/.local ]
    check [ "$(command -v uv)" -ef "${HOME}/bin/uv" ]
    check [ "${PATH%%:*}" = "${PWD}/tv/bin" ]
    check grep -qxF "pip --quiet install --python ${PWD}/tv --upgrade pip setuptools" uv.log
'

run_case "an installed uv that is not yet on PATH is reused, with the hint and completion" '
    export UV_STUB_LOG="${PWD}/uv.log" HOME="${PWD}/home"
    mkdir home shims
    uv_free_path
    make_uv_stub "${HOME}/.local/bin/uv"
    printf "%s\n" "#!/bin/sh" "touch \"${PWD}/curl-called\"" "exit 1" > shims/curl
    chmod +x shims/curl
    export PATH="${PWD}/shims:${PATH}"
    _output="$(. "${CVMFS_VENV}" tv; echo "status=$?"; echo "uv=$(command -v uv)"; complete -p uv > /dev/null 2>&1 && echo completion=yes)"
    check grep -qxF "status=0" <<< "${_output}"
    check [ ! -e curl-called ]
    check grep -qxF "uv=${HOME}/.local/bin/uv" <<< "${_output}"
    check grep -qF "# Add '\''${HOME}/.local/bin'\'' to PATH" <<< "${_output}"
    check grep -qxF "completion=yes" <<< "${_output}"
    check grep -qxF "pip --quiet install --python ${PWD}/tv --upgrade pip setuptools" uv.log
'

run_case "a failed uv download falls back to pip with a warning" '
    export HOME="${PWD}/home"
    mkdir home shims
    uv_free_path
    printf "%s\n" "#!/bin/sh" "exit 22" > shims/curl
    chmod +x shims/curl
    export PATH="${PWD}/shims:${PATH}"
    # Without system site-packages and without pip in the environment, the
    # pip branch itself fails, which proves it ran
    _output="$(. "${CVMFS_VENV}" --no-system-site-packages tv 2>&1; echo "status=$?")"
    check grep -qxF "status=0" <<< "${_output}"
    check grep -q "^WARNING: uv is not available" <<< "${_output}"
    # Proof that the pip branch ran: the environment has no pip, so it fails.
    # A container setup script may provide pip through PYTHONPATH instead.
    [ -f /release_setup.sh ] || check grep -q "^WARNING: Failed to update pip and setuptools with pip" <<< "${_output}"
    check [ -f tv/pyvenv.cfg ]
    check [ ! -e home/.local ]
'

run_case "a pixi install that installs nothing is reported and leaves PATH alone" '
    export HOME="${PWD}/home"
    mkdir home shims
    uv_free_path
    printf "%s\n" "#!/bin/sh" "exit 0" > shims/pixi
    chmod +x shims/pixi
    export PATH="${PWD}/shims:${PATH}"
    _output="$(. "${CVMFS_VENV}" --no-update tv 2>&1; echo "status=$?"; echo "path-tail=${PATH##*:}")"
    check grep -qxF "status=0" <<< "${_output}"
    check grep -q "^WARNING: No working uv" <<< "${_output}"
    check grep -q "^WARNING: uv is not available" <<< "${_output}"
    if grep -q "# Add " <<< "${_output}"; then echo "hint printed for a directory without uv"; exit 1; fi
    check grep -qxF "path-tail=/bin" <<< "${_output}"
'

run_case "a uv that does not work is not used" '
    export UV_STUB_LOG="${PWD}/uv.log" HOME="${PWD}/home" UV_STUB_BROKEN=1
    mkdir home
    uv_free_path
    make_uv_stub "${PWD}/shims/uv"
    export PATH="${PWD}/shims:${PATH}"
    _output="$(. "${CVMFS_VENV}" --no-system-site-packages tv 2>&1; echo "status=$?")"
    check grep -qxF "status=0" <<< "${_output}"
    check grep -q "^WARNING: The uv at .* does not work" <<< "${_output}"
    # Proof that the pip branch ran: the environment has no pip, so it fails.
    # A container setup script may provide pip through PYTHONPATH instead.
    [ -f /release_setup.sh ] || check grep -q "^WARNING: Failed to update pip and setuptools with pip" <<< "${_output}"
    check [ ! -e uv.log ]
'

run_case "a uv that fails to update pip falls back to pip" '
    export UV_STUB_LOG="${PWD}/uv.log" HOME="${PWD}/home" UV_STUB_FAIL_PIP=1
    mkdir home
    uv_free_path
    make_uv_stub "${PWD}/shims/uv"
    export PATH="${PWD}/shims:${PATH}"
    _output="$(. "${CVMFS_VENV}" --no-system-site-packages tv 2>&1; echo "status=$?")"
    check grep -qxF "status=0" <<< "${_output}"
    check grep -q "^WARNING: uv failed to update pip and setuptools, so pip will be used instead" <<< "${_output}"
    # Proof that the pip branch ran: the environment has no pip, so it fails.
    # A container setup script may provide pip through PYTHONPATH instead.
    [ -f /release_setup.sh ] || check grep -q "^WARNING: Failed to update pip and setuptools with pip" <<< "${_output}"
'

run_case "--no-uv installs nothing and uv is not looked for before the environment is validated" '
    export HOME="${PWD}/home"
    mkdir home shims
    uv_free_path
    printf "%s\n" "#!/bin/sh" "touch \"${PWD}/curl-called\"" "exit 1" > shims/curl
    printf "%s\n" "#!/bin/sh" "touch \"${PWD}/pixi-called\"" "exit 1" > shims/pixi
    chmod +x shims/curl shims/pixi
    export PATH="${PWD}/shims:${PATH}"
    . "${CVMFS_VENV}" --no-uv --no-update tv > /dev/null
    check [ $? -eq 0 ]
    check [ ! -e curl-called ]
    check [ ! -e pixi-called ]
    deactivate
    # A refused target must not trigger an install either
    mkdir notavenv
    . "${CVMFS_VENV}" notavenv 2> /dev/null
    check [ $? -eq 1 ]
    check [ ! -e curl-called ]
    check [ ! -e pixi-called ]
'

run_case "a uv that only lives in the previously active environment is not relied on" '
    export UV_STUB_LOG="${PWD}/uv.log" HOME="${PWD}/home"
    mkdir home shims
    uv_free_path
    make_uv_stub "${PWD}/uv-stub"
    export UV_STUB_SOURCE="${PWD}/uv-stub"
    make_fake_installer "${PWD}/fake-installer.sh"
    printf "%s\n" "#!/bin/bash" "touch \"${PWD}/curl-called\"" "cat \"${PWD}/fake-installer.sh\"" > shims/curl
    chmod +x shims/curl
    export PATH="${PWD}/shims:${PATH}"
    # Environment A carries its own uv; creating B from inside A must not
    # count on it, because activating B removes A/bin from PATH
    "${CVMFS_VENV}" --no-uv --no-update a > /dev/null
    make_uv_stub "${PWD}/a/bin/uv"
    . a/bin/activate
    . "${CVMFS_VENV}" b > /dev/null
    check [ $? -eq 0 ]
    check [ "${VIRTUAL_ENV:-}" = "${PWD}/b" ]
    check [ -e curl-called ]
    check [ "$(command -v uv)" = "${HOME}/.local/bin/uv" ]
    check grep -qxF "pip --quiet install --python ${PWD}/b --upgrade pip setuptools" uv.log
'

echo "# passed ${_passed}, failed ${_failed}"
[ "${_failed}" -eq 0 ]
