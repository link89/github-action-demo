#!/bin/bash
set -euo pipefail
ulimit -c 0 -s unlimited

# Normalize common CP2K forms. All other commands are executed unchanged.
case "${1:-}" in
    "") set -- cp2k --help ;;
    *.inp) set -- cp2k -i "$@" ;;
    cp2k | cp2k.psmp | cp2k.popt | cp2k_shell)
        if [[ $# -ge 2 && "$2" == *.inp ]]; then
            set -- "$1" -i "${@:2}"
        fi
        ;;
    -*) set -- cp2k "$@" ;;
esac
exec "$@"
