#!/bin/bash
set -e

git clone --recursive -b support/v2025.1 https://github.com/cp2k/cp2k.git /opt/cp2k

pushd /opt/cp2k
# fix dftd4 issue
git show b66934358f8d9e2bb20b8486fae294a919db9ab6 -- tools/toolchain/scripts/stage8/install_dftd4.sh | \
    git apply -
popd


# Build CP2K toolchain for target CPU skylake-avx512
pushd /opt/cp2k/tools/toolchain
./install_cp2k_toolchain.sh -j $(nproc) \
    --target-cpu=skylake-avx512 \
    --install-all \
    --with-cusolvermp=no \
    --with-dftd4=no \
    --enable-cuda=no \
    --with-libtorch=system \
    --with-deepmd=system \
    --with-gcc=system \
    --with-openmpi=install
popd

# Build CP2K
pushd /opt/cp2k
cp ./tools/toolchain/install/arch/local.psmp ./arch/
source ./tools/toolchain/install/setup
make -j $(nproc) ARCH=local VERSION=psmp

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

