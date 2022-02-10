new=$(cat <<-EOT
    # Added by https://github.com/matthewfeickert/cvmfs-venv
    if [ -n "\${_OLD_VIRTUAL_PYTHONPATH:-}" ] ; then
        PYTHONPATH="\${_OLD_VIRTUAL_PYTHONPATH:-}"
        export PYTHONPATH
        unset _OLD_VIRTUAL_PYTHONPATH
    fi
EOT
)

_back=$(cat <<-EOT
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
$new
.
wq
EOF

ed out.sh <<EOF
60i
$_back
.
wq
EOF

cat out.sh
