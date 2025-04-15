#!/bin/bash
set -e

# install system dependencies
apt-get update -qq
apt-get install -qq --no-install-recommends \
    g++ gcc gfortran openssh-client python3 python3-pip \
    bzip2 ca-certificates git make patch pkg-config unzip wget curl zlib1g-dev
apt-get clean
rm -rf /var/lib/apt/lists/*

# install tensorflow
pip install --no-cache-dir tensorflow

# install libtorch
pushd /opt
LIBTORCH_URL=https://download.pytorch.org/libtorch/cu124/libtorch-cxx11-abi-shared-with-deps-2.6.0%2Bcu124.zip
# LIBTORCH_URL=https://download.pytorch.org/libtorch/cpu/libtorch-cxx11-abi-shared-with-deps-1.12.1%2Bcpu.zip
wget -q $LIBTORCH_URL -O libtorch.zip
unzip libtorch.zip && rm libtorch.zip
ln -s /opt/libtorch/include/* /usr/local/include/
ln -s /opt/libtorch/lib/* /usr/local/lib/
popd

# install libdeepmd
pushd /opt
wget -q  https://github.com/deepmodeling/deepmd-kit/releases/download/v3.0.2/libdeepmd_c.tar.gz \
    -O libdeempd_c.tgz
tar -xzf libdeempd_c.tgz && rm libdeempd_c.tgz
ln -s /opt/libdeepmd_c/include/* /usr/local/include/
ln -s /opt/libdeepmd_c/lib/* /usr/local/lib/
popd