#!/bin/bash
set -euo pipefail
ulimit -c 0 -s unlimited
if [[ $# -eq 0 ]]; then
    set -- cp2k --help
elif [[ "$1" == *.inp ]]; then
    input=$1
    shift
    set -- cp2k -i "$input" "$@"
elif [[ "$1" == -* ]]; then
    set -- cp2k "$@"
fi
exec "$@"
