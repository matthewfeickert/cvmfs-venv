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

cp _activate_empty.sh out.sh
ed out.sh <<EOF
16i
$_SET_PYTHONPATH
.
wq
EOF

ed out.sh <<EOF
60i
$_RECOVER_OLD_PYTHONPATH
.
wq
EOF

cat out.sh

unset _SET_PYTHONPATH
unset _RECOVER_OLD_PYTHONPATH
