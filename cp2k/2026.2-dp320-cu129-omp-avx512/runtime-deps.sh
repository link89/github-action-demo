#!/bin/bash
set -euo pipefail

apt-get update -qq
apt-get install -qq --no-install-recommends \
    ca-certificates libmunge2 libucx0 libibverbs1 librdmacm1 \
    rdma-core libmlx5-1 libopenmpi3 openmpi-bin python3
apt-get clean
rm -rf /var/lib/apt/lists/*

PYTHON_LIB=/usr/local/lib/python3.10/dist-packages
{
    printf '%s\n' /usr/local/lib /usr/local/lib64
    printf '%s\n' "$PYTHON_LIB/torch/lib" "$PYTHON_LIB/tensorflow"
    if [[ -d "$PYTHON_LIB/nvidia" ]]; then
        find "$PYTHON_LIB/nvidia" -type d -name lib -print
    fi
} > /etc/ld.so.conf.d/deepmd-frameworks.conf
ldconfig
