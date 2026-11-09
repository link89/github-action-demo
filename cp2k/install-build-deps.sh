#!/bin/bash
set -euo pipefail

"$(dirname "$0")/install-runtime-deps.sh"

apt-get update -qq
apt-get install -qq --no-install-recommends \
    g++ gcc gfortran git m4 make patch pkg-config \
    bzip2 curl openssh-client python3-dev python3-pip unzip wget zlib1g-dev \
    libmunge-dev libucx-dev libibverbs-dev librdmacm-dev
apt-get clean
rm -rf /var/lib/apt/lists/*

python3 -m pip install --no-cache-dir 'cmake>=3.25.2,<4' ninja

"$(dirname "$0")/build-openmpi.sh"
