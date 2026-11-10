#!/bin/bash
set -euo pipefail

export CONDA_OVERRIDE_CUDA=12.9
mkdir -p /usr/local/conda-meta
touch /usr/local/conda-meta/history
/opt/conda/bin/mamba install -y --prefix /usr/local --file /tmp/runtime-explicit.txt
/opt/conda/bin/mamba clean --all --yes
mkdir -p /usr/local/share/cp2k
mv /tmp/runtime-explicit.txt /usr/local/share/cp2k/runtime-explicit.txt

PYTHON_LIB=/usr/local/lib/python3.12/site-packages
{
    printf '%s\n' /usr/local/lib /usr/local/lib64
    printf '%s\n' "$PYTHON_LIB/torch/lib" "$PYTHON_LIB/tensorflow"
    printf '%s\n' /usr/local/targets/x86_64-linux/lib
} > /etc/ld.so.conf.d/deepmd-frameworks.conf
ldconfig
