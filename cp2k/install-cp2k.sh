#!/bin/bash
set -euo pipefail

for binary in cp2k dumpdcd graph xyz2dcd; do
    ln -sf "${binary}.psmp" "/usr/local/bin/${binary}"
done
ln -sf cp2k.psmp /usr/local/bin/cp2k_shell
ln -sf cp2k.psmp /usr/local/bin/cp2k.popt
