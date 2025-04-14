#!/bin/bash
set -e
cd /opt

# install system dependencies
apt-get update -qq
apt-get install -qq --no-install-recommends \
    g++ gcc gfortran openssh-client python3 python3-pip \
    bzip2 ca-certificates git make patch pkg-config unzip wget curl zlib1g-dev
apt-get clean
rm -rf /var/lib/apt/lists/*

# install tensorflow
pip install --no-cache-dir tensorflow

pushd /opt
# install libtorch
wget -O libtorch.zip https://download.pytorch.org/libtorch/cu124/libtorch-cxx11-abi-shared-with-deps-2.6.0%2Bcu124.zip
unzip libtorch.zip && rm libtorch.zip
mkdir -p /usr/local/lib /usr/local/include
ln -s /opt/libtorch/lib/* /usr/local/lib/
ln -s /opt/libtorch/include/* /usr/local/include/
popd