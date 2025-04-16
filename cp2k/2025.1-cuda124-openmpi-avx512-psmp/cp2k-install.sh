#!/bin/bash
set -e

for binary in cp2k dumpdcd graph xyz2dcd; do
    ln -sf /opt/cp2k/exe/local/${binary}.psmp /usr/local/bin/${binary}
done

ln -sf /opt/cp2k/exe/local/cp2k.psmp /usr/local/bin/cp2k_shell
ln -sf /opt/cp2k/exe/local/cp2k.psmp /usr/local/bin/cp2k.popt
