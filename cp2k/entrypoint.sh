#!/bin/bash
set -euo pipefail
ulimit -c 0 -s unlimited
exec "$@"
