#!/bin/bash
set -euo pipefail

"$(dirname "$0")/runtime-deps.sh"

apt-get update -qq
apt-get install -qq --no-install-recommends \
    g++ gcc gfortran git make patch pkg-config \
    bzip2 curl openssh-client python3 python3-pip unzip wget zlib1g-dev \
    libmunge-dev libucx-dev libibverbs-dev librdmacm-dev libopenmpi-dev
apt-get clean
rm -rf /var/lib/apt/lists/*

mkdir -p /tmp/deepmd-build
wget -q https://github.com/deepmodeling/deepmd-kit/releases/download/v3.0.2/libdeepmd_c.tar.gz \
    -O /tmp/libdeepmd_c.tar.gz
tar -xzf /tmp/libdeepmd_c.tar.gz -C /tmp/deepmd-build
cp -a /tmp/deepmd-build/libdeepmd_c/include/. /usr/local/include/
rm -rf /tmp/deepmd-build /tmp/libdeepmd_c.tar.gz
