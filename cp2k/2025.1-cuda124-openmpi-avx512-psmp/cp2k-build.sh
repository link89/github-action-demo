#!/bin/bash
set -e
cd $(dirname $0)

./dev-setup.sh

mkdir -p /mnt/share/cp2k
ln -s /mnt/share/cp2k /opt/cp2k
git clone --recursive -b support/v2025.1 https://github.com/cp2k/cp2k.git /opt/cp2k

pushd /opt/cp2k
# fix dftd4 issue
git show b66934358f8d9e2bb20b8486fae294a919db9ab6 -- tools/toolchain/scripts/stage8/install_dftd4.sh | git apply -
git show 0991fe12da12d91042194299b21c123570a769dd -- tools/toolchain/scripts/stage8/install_dftd4.sh | git apply -
popd

# Build CP2K toolchain for target CPU skylake-avx512
pushd /opt/cp2k/tools/toolchain
./install_cp2k_toolchain.sh -j $(nproc) \
    --target-cpu=skylake-avx512 \
    --install-all \
    --with-cusolvermp=no \
    --enable-cuda=no \
    --with-gcc=system \
    --with-deepmd=install \
    --with-openmpi=install
popd

# Build CP2K
pushd /opt/cp2k
cp ./tools/toolchain/install/arch/local.psmp ./arch/
source ./tools/toolchain/install/setup
make -j $(nproc) ARCH=local VERSION=psmp

# Remove unnecessary files
unlink ./exe/local/cp2k.popt
unlink ./exe/local/cp2k_shell.psmp

# Install CP2K
DIST_DIR=/mnt/share/dist

mkdir -p $DIST_DIR/tools/toolchain/install
mkdir -p $DIST_DIR/tools/toolchain/scripts
mkdir -p $DIST_DIR/src/grid
mkdir -p $DIST_DIR/exe
mkdir -p $DIST_DIR/tools

# Install toolchain
for libdir in $(ldd ./exe/local/cp2k.psmp |
                grep /opt/cp2k/tools/toolchain/install |
                awk '{print $3}' | cut -d/ -f7 |
                sort | uniq) setup; do
    mv ./tools/toolchain/install/${libdir} $DIST_DIR/tools/toolchain/install
done
mv ./tools/toolchain/scripts/tool_kit.sh $DIST_DIR/tools/toolchain/scripts

# # Install CP2K binaries
mv ./exe/local $DIST_DIR/exe/

# Install CP2K regression tests
mv ./tests $DIST_DIR/
mv ./tools/regtesting $DIST_DIR/tools/
mv ./src/grid/sample_tasks $DIST_DIR/src/grid/

# Install CP2K database files
mv ./data $DIST_DIR/

popd