#!/bin/bash
set -euo pipefail

apt-get update -qq
apt-get install -qq --no-install-recommends \
    ca-certificates libmunge2 libucx0 libibverbs1 librdmacm1 \
    rdma-core libmlx5-1 libopenmpi3 openmpi-bin wget

apt-get clean
rm -rf /var/lib/apt/lists/*

mkdir -p /tmp/deepmd-runtime
wget -q https://github.com/deepmodeling/deepmd-kit/releases/download/v3.0.2/libdeepmd_c.tar.gz \
    -O /tmp/libdeepmd_c.tar.gz
tar -xzf /tmp/libdeepmd_c.tar.gz -C /tmp/deepmd-runtime
cp -a /tmp/deepmd-runtime/libdeepmd_c/lib/. /usr/local/lib/
ldconfig
apt-get purge -qq -y wget
rm -rf /tmp/deepmd-runtime /tmp/libdeepmd_c.tar.gz
