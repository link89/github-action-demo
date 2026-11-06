#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

./install-build-deps.sh
test "$(command -v mpicc)" = /usr/local/bin/mpicc
test "$(command -v mpifort)" = /usr/local/bin/mpifort
mpicc --showme:link
export CC=${CC:-gcc} CXX=${CXX:-g++} FC=${FC:-gfortran}
export F77=${F77:-gfortran} F90=${F90:-gfortran}
export OMPI_CC=${OMPI_CC:-gcc} OMPI_CXX=${OMPI_CXX:-g++} OMPI_FC=${OMPI_FC:-gfortran}
export PYTHONPATH=/mnt/scratch/python
export TMPDIR=/mnt/scratch/tmp
mkdir -p "$PYTHONPATH" "$TMPDIR"

./build-deepmd.sh

curl -fL --retry 3 https://github.com/cp2k/cp2k/archive/refs/tags/v2026.2.tar.gz \
    -o /mnt/scratch/cp2k-v2026.2.tar.gz
tar -xzf /mnt/scratch/cp2k-v2026.2.tar.gz -C /mnt/scratch
CP2K_SRC=/mnt/scratch/cp2k-2026.2

# The toolchain requires PWD to match its physical source directory.
CP2K_SRC=$(cd "$CP2K_SRC" && pwd -P)

pushd "$CP2K_SRC"
git apply /mnt/scripts/openblas-target.patch
popd

pushd "$CP2K_SRC/tools/toolchain"
./install_cp2k_toolchain.sh -j "$(nproc)" \
    --target-cpu=skylake-avx512 \
    --install-all \
    --with-cusolvermp=no \
    --enable-cuda=no \
    --with-gcc=system \
    --with-deepmd=/usr/local \
    --with-openmpi=system
popd

pushd "$CP2K_SRC"
# Load dependency prefixes exported by the 2026.2 toolchain.
source ./tools/toolchain/install/setup
BUILD_DIR=/mnt/scratch/cp2k-build
ARCH_FLAGS='-O3 -g -march=skylake-avx512 -mtune=skylake-avx512'
# Upstream Release adds -march=native. RelWithDebInfo lets us explicitly
# select the target CPU for all three languages without host CPU overrides.
cmake -S "$CP2K_SRC" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_Fortran_COMPILER="$FC" \
    -DCMAKE_C_FLAGS_RELWITHDEBINFO="$ARCH_FLAGS" \
    -DCMAKE_CXX_FLAGS_RELWITHDEBINFO="$ARCH_FLAGS" \
    -DCMAKE_Fortran_FLAGS_RELWITHDEBINFO="$ARCH_FLAGS" \
    -DMPI_C_COMPILER=/usr/local/bin/mpicc \
    -DMPI_CXX_COMPILER=/usr/local/bin/mpicxx \
    -DMPI_Fortran_COMPILER=/usr/local/bin/mpifort \
    -DCP2K_USE_EVERYTHING=ON \
    -DCP2K_USE_MPI=ON -DCP2K_USE_DEEPMD=ON \
    -DCP2K_USE_DLAF=OFF -DCP2K_USE_PEXSI=OFF -DCP2K_USE_OPENPMD=OFF \
    -DCP2K_USE_SIRIUS_VCSQNM=ON \
    -DCP2K_USE_SIRIUS_DFTD3=ON -DCP2K_USE_SIRIUS_DFTD4=ON \
    -DCP2K_USE_ACCEL=NONE \
    -DDeePMD_DIR=/usr/local/lib/cmake/DeePMD \
    -DCP2K_DATA_DIR=/usr/local/share/cp2k/data \
    -DBUILD_SHARED_LIBS=ON
cmake --build "$BUILD_DIR" --parallel "$(nproc)"
DESTDIR=/mnt/scratch/dist cmake --install "$BUILD_DIR"

DIST=/mnt/scratch/dist/usr/local
# Include staged libcp2k when resolving the installed executable's dependencies.
export LD_LIBRARY_PATH="$DIST/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
mkdir -p "$DIST/lib" "$DIST/include"
cp -a /usr/local/lib/libdeepmd*.so* "$DIST/lib/"
cp -a /usr/local/include/deepmd "$DIST/include/"

# ldd traverses transitive dependencies, including libcp2k's toolchain libraries.
ldd "$DIST/bin/cp2k.psmp" | tee /mnt/scratch/cp2k-ldd
if grep -q 'not found' /mnt/scratch/cp2k-ldd; then
    echo 'CP2K has unresolved build-time libraries' >&2
    exit 1
fi
awk -v prefix="$CP2K_SRC/tools/toolchain/install/" \
    'index($3, prefix) == 1 {print $3}' /mnt/scratch/cp2k-ldd | \
    while IFS= read -r library; do cp -aL "$library" "$DIST/lib/"; done

test -s "$DIST/share/cp2k/data/BASIS_MOLOPT"
# The AVX-512 regression run is diagnostic on GitHub-hosted runners.
mkdir -p /mnt/scratch/regtest
CP2K_DATA_DIR="$DIST/share/cp2k/data" ./tests/do_regtest.py \
    --mpiexec "mpiexec --bind-to none" --maxtasks 4 \
    --workbasedir /mnt/scratch/regtest "$@" "$DIST/bin" psmp || true
popd

# Preserve the exact Python packages that DeePMD linked against.
PYTHON_LIB=/usr/local/lib/python3.10/dist-packages
mkdir -p "/mnt/scratch/dist${PYTHON_LIB}"
cp -a "$PYTHONPATH/." "/mnt/scratch/dist${PYTHON_LIB}/"

printf 'Built libraries:\n'
ldd "$DIST/bin/cp2k.psmp"
