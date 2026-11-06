#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

./install-build-deps.sh
export CC=${CC:-gcc} CXX=${CXX:-g++} FC=${FC:-gfortran}
export F77=${F77:-gfortran} F90=${F90:-gfortran}
export OMPI_CC=${OMPI_CC:-gcc} OMPI_CXX=${OMPI_CXX:-g++} OMPI_FC=${OMPI_FC:-gfortran}

CP2K_SRC=/mnt/scratch/cp2k
git clone --recursive -b support/v2025.1 https://github.com/cp2k/cp2k.git "$CP2K_SRC"

# The toolchain requires PWD to match its physical source directory.
CP2K_SRC=$(cd "$CP2K_SRC" && pwd -P)

pushd "$CP2K_SRC"
# fix dftd4 issue
git show b66934358f8d9e2bb20b8486fae294a919db9ab6 -- tools/toolchain/scripts/stage8/install_dftd4.sh | git apply -
git show 0991fe12da12d91042194299b21c123570a769dd -- tools/toolchain/scripts/stage8/install_dftd4.sh | git apply -
git apply /mnt/scripts/openblas-target.patch
popd

# Build CP2K toolchain for target CPU skylake-avx512
pushd "$CP2K_SRC/tools/toolchain"
./install_cp2k_toolchain.sh -j "$(nproc)" \
    --target-cpu=skylake-avx512 \
    --install-all \
    --with-cusolvermp=no \
    --enable-cuda=no \
    --with-gcc=system \
    --with-deepmd=system \
    --with-openmpi=system
popd

# Build CP2K
pushd "$CP2K_SRC"
cp ./tools/toolchain/install/arch/local.psmp ./arch/
source ./tools/toolchain/install/setup
printf 'Compilers: CC=%s CXX=%s FC=%s\n' "$CC" "$CXX" "$FC"
printf 'Generated architecture flags:\n'
grep -E 'march=|avx512' ./arch/local.psmp || true
ARCH_FLAGS='-march=skylake-avx512 -mtune=skylake-avx512'
export CFLAGS="${CFLAGS:+$CFLAGS }$ARCH_FLAGS"
export CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }$ARCH_FLAGS"
export FFLAGS="${FFLAGS:+$FFLAGS }$ARCH_FLAGS"
export FCFLAGS="${FCFLAGS:+$FCFLAGS }$ARCH_FLAGS"
export F90FLAGS="${F90FLAGS:+$F90FLAGS }$ARCH_FLAGS"
printf 'CP2K architecture flags: %s\n' "$ARCH_FLAGS"
make -j "$(nproc)" ARCH=local VERSION=psmp

# GitHub-hosted runners lack AVX-512; this test is diagnostic only.
mkdir -p /mnt/scratch/regtest
./tests/do_regtest.py --mpiexec "mpiexec --bind-to none" --maxtasks 4 \
    --workbasedir /mnt/scratch/regtest "$@" ./exe/local psmp || true

# Remove unnecessary files
unlink ./exe/local/cp2k.popt
unlink ./exe/local/cp2k_shell.psmp

# Install CP2K
DIST_DIR=/mnt/scratch/dist
mkdir -p "$DIST_DIR/bin" "$DIST_DIR/lib" "$DIST_DIR/share/cp2k"

# Collect the toolchain libraries linked by CP2K into a standard loader path.
ldd ./exe/local/cp2k.psmp | awk -v prefix="$CP2K_SRC/tools/toolchain/install/" 'index($3, prefix) == 1 {print $3}' | \
    while IFS= read -r library; do
        cp -aL "$library" "$DIST_DIR/lib/"
    done

mv ./exe/local/* "$DIST_DIR/bin/"
mv ./data "$DIST_DIR/share/cp2k/"

popd
