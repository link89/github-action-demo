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
$DIST_DIR=/mnt/share/dist
mkdir -p $DIST_DIR/toolchain/install $DIST_DIR/toolchain/scripts

for libdir in $(ldd ./exe/local/cp2k.psmp |
                grep /opt/cp2k/tools/toolchain/install |
                awk '{print $3}' | cut -d/ -f7 |
                sort | uniq) setup; do
    cp -ar ./tools/toolchain/install/${libdir} $DIST_DIR/toolchain/install
done
cp ./tools/toolchain/scripts/tool_kit.sh $DIST_DIR/toolchain/scripts


# # Install CP2K binaries
cp -ar ./exe/local/ $DIST_DIR/exe/local/

# # Install CP2K regression tests
# COPY --from=share ./cp2k/tests/ /opt/cp2k/tests/
# COPY --from=share ./cp2k/tools/regtesting/ /opt/cp2k/tools/regtesting/
# COPY --from=share ./cp2k/src/grid/sample_tasks/ /opt/cp2k/src/grid/sample_tasks/
#
# # Install CP2K database files
# COPY --from=share ./cp2k/data/ /opt/cp2k/data/
#
# # Install shared libraries required by the CP2K binaries
# COPY --from=share ./toolchain/ /opt/cp2k/tools/toolchain/




popd