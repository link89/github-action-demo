#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

./build-deps.sh
test "$(command -v mpicc)" = /usr/local/bin/mpicc
test "$(command -v mpifort)" = /usr/local/bin/mpifort
mpicc --showme:link
export CC=${CC:-gcc} CXX=${CXX:-g++} FC=${FC:-gfortran}
export F77=${F77:-gfortran} F90=${F90:-gfortran}
export OMPI_CC=${OMPI_CC:-gcc} OMPI_CXX=${OMPI_CXX:-g++} OMPI_FC=${OMPI_FC:-gfortran}
export PYTHONPATH=/mnt/scratch/python
export TMPDIR=/mnt/scratch/tmp
mkdir -p "$PYTHONPATH" "$TMPDIR"

./deepmd-build.sh

curl -fL --retry 3 https://github.com/cp2k/cp2k/archive/refs/tags/v2026.2.tar.gz \
    -o /mnt/scratch/cp2k-v2026.2.tar.gz
tar -xzf /mnt/scratch/cp2k-v2026.2.tar.gz -C /mnt/scratch
ln -s /mnt/scratch/cp2k-2026.2 /opt/cp2k

pushd /opt/cp2k/tools/toolchain
./install_cp2k_toolchain.sh -j "$(nproc)" \
    --target-cpu=skylake-avx512 \
    --install-all \
    --with-cusolvermp=no \
    --enable-cuda=no \
    --with-gcc=system \
    --with-deepmd=system \
    --with-openmpi=system
popd

pushd /opt/cp2k
cp ./tools/toolchain/install/arch/local.psmp ./arch/
source ./tools/toolchain/install/setup
ARCH_FLAGS='-march=skylake-avx512 -mtune=skylake-avx512'
export CFLAGS="${CFLAGS:+$CFLAGS }$ARCH_FLAGS"
export CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }$ARCH_FLAGS"
export FFLAGS="${FFLAGS:+$FFLAGS }$ARCH_FLAGS"
export FCFLAGS="${FCFLAGS:+$FCFLAGS }$ARCH_FLAGS"
export F90FLAGS="${F90FLAGS:+$F90FLAGS }$ARCH_FLAGS"
printf 'Compilers: CC=%s CXX=%s FC=%s\nCP2K flags: %s\n' "$CC" "$CXX" "$FC" "$ARCH_FLAGS"
make -j "$(nproc)" ARCH=local VERSION=psmp

# The GitHub-hosted runner cannot execute this AVX-512 binary.
mkdir -p /mnt/scratch/regtest
./tests/do_regtest.py --mpiexec "mpiexec --bind-to none" --maxtasks 4 \
    --workbasedir /mnt/scratch/regtest "$@" ./exe/local psmp || true

DIST=/mnt/scratch/dist/usr/local
mkdir -p "$DIST/bin" "$DIST/lib" "$DIST/include" "$DIST/share/cp2k"
cp -a /usr/local/lib/libdeepmd*.so* "$DIST/lib/"
cp -a /usr/local/include/deepmd "$DIST/include/"

ldd ./exe/local/cp2k.psmp | awk '$3 ~ /^\/opt\/cp2k\/tools\/toolchain\/install\// {print $3}' | \
    while IFS= read -r library; do cp -aL "$library" "$DIST/lib/"; done

rm -f ./exe/local/cp2k.popt ./exe/local/cp2k_shell.psmp
mv ./exe/local/* "$DIST/bin/"
mv ./data "$DIST/share/cp2k/"
popd

# Preserve the exact Python packages that DeePMD linked against.
PYTHON_LIB=/usr/local/lib/python3.10/dist-packages
mkdir -p "/mnt/scratch/dist${PYTHON_LIB}"
cp -a "$PYTHONPATH/." "/mnt/scratch/dist${PYTHON_LIB}/"

printf 'Built libraries:\n'
ldd "$DIST/bin/cp2k.psmp"
