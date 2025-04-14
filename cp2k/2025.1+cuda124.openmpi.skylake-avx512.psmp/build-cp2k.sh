#!/bin/bash
set -e

git clone --recursive -b support/v2025.1 https://github.com/cp2k/cp2k.git /opt/cp2k

# Build CP2K toolchain for target CPU skylake-avx512
pushd /opt/cp2k/tools/toolchain
./install_cp2k_toolchain.sh -j 8 \
    --target-cpu=skylake-avx512 \
    --install-all \
    --with-cusolvermp=no \
    --enable-cuda=yes \
    --with-libtorch=system \
    --with-deepmd=system \
    --with-gcc=system \
    --with-openmpi=install
popd

# Build CP2K
pushd /opt/cp2k
cp ./tools/toolchain/install/arch/local.psmp ./arch/
source ./tools/toolchain/install/setup
make -j 8 ARCH=local VERSION=psmp

mkdir -p /toolchain/install /toolchain/scripts
for libdir in $(ldd ./exe/local/cp2k.psmp |
                grep /opt/cp2k/tools/toolchain/install |
                awk '{print $3}' | cut -d/ -f7 |
                sort | uniq) setup; do
    cp -ar /opt/cp2k/tools/toolchain/install/${libdir} /toolchain/install
done

cp /opt/cp2k/tools/toolchain/scripts/tool_kit.sh /toolchain/scripts
unlink ./exe/local/cp2k.popt
unlink ./exe/local/cp2k_shell.psmp
popd

