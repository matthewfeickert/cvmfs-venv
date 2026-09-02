#!/bin/bash
#
# Behavioural tests for cvmfs-venv.sh.
#
# Every invocation of cvmfs-venv passes --no-uv --no-update, so the tests need
# no network access and never install anything. Each case runs in a fresh
# subshell and working directory; a case passes when its snippet exits 0.
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
    if [ -d /cvmfs/atlas.cern.ch ]; then
        echo "skipped: /cvmfs/atlas.cern.ch is mounted"
        exit 0
    fi
    . "${CVMFS_VENV}" --no-uv --no-update --setup "lsetup views" nocvmfs 2> /dev/null
    _status=$?
    check [ "${_status}" -eq 1 ]
    check [ ! -d nocvmfs ]
    exit 0
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
    _before="$(compgen -v; compgen -A function)"
    . "${CVMFS_VENV}" --no-uv --no-update tv
    deactivate
    _after="$(compgen -v; compgen -A function)"
    # A stock venv activate/deactivate cycle itself leaves _OLD_VIRTUAL_PS1 and PS1.
    _new="$(comm -13 <(echo "${_before}" | sort) <(echo "${_after}" | sort) \
        | grep -vx -e _before -e _after -e PIPESTATUS -e _OLD_VIRTUAL_PS1 -e PS1 -e PIP_REQUIRE_VIRTUALENV)"
    if [ -n "${_new}" ]; then echo "leaked: ${_new}"; exit 1; fi
'

run_case "sourcing works under set -e and set -u" '
    set -eu
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
    set -eu
    export PYTHONPATH=/fake/lcg
    . "${CVMFS_VENV}" --no-uv --no-update tv > /dev/null
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

echo "# passed ${_passed}, failed ${_failed}"
[ "${_failed}" -eq 0 ]
