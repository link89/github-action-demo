#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CP2K_ENABLE_CUDA="${CP2K_ENABLE_CUDA:-0}"
CP2K_GPU_ARCH="${CP2K_GPU_ARCH:-A100}"
CP2K_CUDA_ARCHITECTURES="${CP2K_CUDA_ARCHITECTURES:-80;86;89;90}"
case "$CP2K_ENABLE_CUDA" in
    0)
        enable_cuda=no
        cp2k_accel=NONE
        cp2k_variant=cpu
        ;;
    1)
        enable_cuda=yes
        cp2k_accel=CUDA
        cp2k_variant=cuda
        ;;
    *)
        echo 'CP2K_ENABLE_CUDA must be 0 or 1' >&2
        exit 1
        ;;
esac

printf 'Building cp2k 2026.2 with conda/MKL, acceleration %s, source %s\n' \
    "$cp2k_accel" "${SOURCE_COMMIT:-unknown}"
df -h /mnt/scratch
mount | grep '/mnt/scratch' || true

./install-build-deps.sh
# Conda activation hooks may read optional variables before testing whether
# they are set (for example CUDA's NVCC_PREPEND_FLAGS). Keep errexit/pipefail,
# but disable nounset while loading third-party activation scripts.
set +u
source /opt/conda/etc/profile.d/conda.sh
conda activate /usr/local
set -u
export PYTHONNOUSERSITE=1
export MKLROOT=/usr/local
export CMAKE_PREFIX_PATH=/usr/local
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
printf '%s\n' /usr/local/lib /usr/local/lib64 \
    /usr/local/lib/python3.12/site-packages/torch/lib \
    /usr/local/lib/python3.12/site-packages/tensorflow \
    /usr/local/targets/x86_64-linux/lib > /etc/ld.so.conf.d/cp2k-conda.conf
ldconfig
test "$(command -v mpicc)" = /usr/local/bin/mpicc
test "$(command -v mpifort)" = /usr/local/bin/mpifort
mpirun --version | grep -Eq '5\.0\.'
mpicc --showme:link
export CC=${CC:-gcc} CXX=${CXX:-g++} FC=${FC:-gfortran}
export F77=${F77:-gfortran} F90=${F90:-gfortran}
export OMPI_CC="$CC" OMPI_CXX="$CXX" OMPI_FC="$FC"
export TMPDIR=/mnt/scratch/tmp
mkdir -p "$TMPDIR"

if [[ "$CP2K_ENABLE_CUDA" == 1 ]]; then
    CUDA_ROOT=/usr/local
    CUDA_NVCC=$(command -v nvcc || true)
    if [[ -z "$CUDA_NVCC" && -x "$CUDA_ROOT/bin/nvcc" ]]; then
        CUDA_NVCC="$CUDA_ROOT/bin/nvcc"
    fi
    if [[ -z "$CUDA_NVCC" && -x "$CUDA_ROOT/targets/x86_64-linux/bin/nvcc" ]]; then
        CUDA_NVCC="$CUDA_ROOT/targets/x86_64-linux/bin/nvcc"
    fi
    if [[ -z "$CUDA_NVCC" ]]; then
        echo 'nvcc is required for the CUDA build' >&2
        exit 1
    fi
    export NVCC="$CUDA_NVCC"
    export CUDA_HOME="$CUDA_ROOT" CUDA_PATH="$CUDA_ROOT"
    export CUDAToolkit_ROOT="$CUDA_ROOT"
    export PATH="$(dirname "$NVCC"):$PATH"
    "$NVCC" --version
fi

./build-deepmd.sh

curl -fL --retry 3 https://github.com/cp2k/cp2k/archive/refs/tags/v2026.2.tar.gz \
    -o /mnt/scratch/cp2k-v2026.2.tar.gz
tar -xzf /mnt/scratch/cp2k-v2026.2.tar.gz -C /mnt/scratch
CP2K_SRC=/mnt/scratch/cp2k-2026.2

# The toolchain requires PWD to match its physical source directory.
CP2K_SRC=$(cd "$CP2K_SRC" && pwd -P)

pushd "$CP2K_SRC"
git apply /mnt/scripts/mkl-layout.patch
popd

toolchain_args=(
    -j "$(nproc)"
    --target-cpu=icelake-server
    --install-all
    --with-cusolvermp=no
    --enable-cuda="$enable_cuda"
    --with-gcc=system
    --with-intel=no
    --with-deepmd=/usr/local
    --with-libtorch=/usr/local
    --with-mkl=system
    --with-gmp=system
    --with-openblas=no
    --with-openmpi=system
)
if [[ "$CP2K_ENABLE_CUDA" == 1 ]]; then
    toolchain_args+=(--gpu-ver="$CP2K_GPU_ARCH")
fi

pushd "$CP2K_SRC/tools/toolchain"
./install_cp2k_toolchain.sh "${toolchain_args[@]}"
popd

pushd "$CP2K_SRC"
# Load dependency prefixes exported by the 2026.2 toolchain.
source ./tools/toolchain/install/setup
BUILD_DIR=/mnt/scratch/cp2k-build
ARCH_FLAGS='-O3 -g -march=icelake-server -mtune=icelake-server'
# Upstream Release adds -march=native. RelWithDebInfo lets us explicitly
# select the target CPU for all three languages without host CPU overrides.
# Do not override CMAKE_INSTALL_LIBDIR here: CP2K declares it as a cache PATH,
# so a relative command-line value resolves against CP2K's source directory.
cmake_args=(
    -S "$CP2K_SRC" -B "$BUILD_DIR" -G Ninja
    -DCMAKE_BUILD_TYPE=RelWithDebInfo
    -DCMAKE_INSTALL_PREFIX=/usr/local
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX"
    -DCMAKE_Fortran_COMPILER="$FC"
    -DCMAKE_C_FLAGS_RELWITHDEBINFO="$ARCH_FLAGS"
    -DCMAKE_CXX_FLAGS_RELWITHDEBINFO="$ARCH_FLAGS"
    -DCMAKE_Fortran_FLAGS_RELWITHDEBINFO="$ARCH_FLAGS"
    -DMPI_C_COMPILER=/usr/local/bin/mpicc
    -DMPI_CXX_COMPILER=/usr/local/bin/mpicxx
    -DMPI_Fortran_COMPILER=/usr/local/bin/mpifort
    -DCP2K_USE_EVERYTHING=ON
    -DCP2K_USE_MPI=ON -DCP2K_USE_DEEPMD=ON
    -DCP2K_USE_DLAF=OFF -DCP2K_USE_PEXSI=OFF -DCP2K_USE_OPENPMD=OFF
    -DCP2K_USE_SIRIUS_VCSQNM=ON
    -DCP2K_USE_SIRIUS_DFTD3=ON -DCP2K_USE_SIRIUS_DFTD4=ON
    -DCP2K_USE_ACCEL="$cp2k_accel"
    -DCP2K_BLAS_VENDOR=MKL -DCP2K_SCALAPACK_VENDOR=MKL
    -DCP2K_BLAS_INTERFACE=32bits -DCP2K_BLAS_THREADING=sequential
    -DCP2K_USE_FFTW3_WITH_MKL=ON
    -DMKL_ROOT=/usr/local
    -DDeePMD_DIR=/usr/local/lib/cmake/DeePMD
    -DCP2K_DATA_DIR=/usr/local/share/cp2k/data
    -DBUILD_SHARED_LIBS=ON
)
if [[ "$CP2K_ENABLE_CUDA" == 1 ]]; then
    cmake_args+=(
        -DCMAKE_CUDA_COMPILER="$NVCC"
        -DCMAKE_CUDA_ARCHITECTURES="$CP2K_CUDA_ARCHITECTURES"
        -DCUDAToolkit_ROOT=/usr/local
        -DSPLA_ROOT="${SPLA_ROOT}-cuda"
        -DCP2K_USE_SPLA_GEMM_OFFLOADING=ON
    )
fi

cmake "${cmake_args[@]}"
grep -q '^CP2K_BLAS_VENDOR:STRING=MKL$' "$BUILD_DIR/CMakeCache.txt"
grep -Fq "CP2K_USE_ACCEL:STRING=$cp2k_accel" "$BUILD_DIR/CMakeCache.txt"
if [[ "$CP2K_ENABLE_CUDA" == 1 ]]; then
    grep -Fq "CMAKE_CUDA_ARCHITECTURES:STRING=$CP2K_CUDA_ARCHITECTURES" \
        "$BUILD_DIR/CMakeCache.txt"
fi
cmake --build "$BUILD_DIR" --parallel "$(nproc)"
DESTDIR=/mnt/scratch/dist cmake --install "$BUILD_DIR"

DIST=/mnt/scratch/dist/usr/local
# Include staged libcp2k when resolving the installed executable's dependencies.
export LD_LIBRARY_PATH="$DIST/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
mkdir -p "$DIST/lib" "$DIST/include"
test -e "$DIST/lib/libcp2k.so"
cp -a /usr/local/lib/libdeepmd*.so* "$DIST/lib/"
cp -a /usr/local/include/deepmd "$DIST/include/"
printf '%s\n' "$cp2k_variant" > "$DIST/share/cp2k/build-variant"

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
# The build container has no GPU. CUDA regtests run only in a GPU-enabled job.
if [[ "$CP2K_ENABLE_CUDA" == 0 ]] && grep -qw avx512f /proc/cpuinfo; then
    mkdir -p /mnt/scratch/regtest
    OMPI_ALLOW_RUN_AS_ROOT=1 OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 OMP_NUM_THREADS=1 \
        CP2K_DATA_DIR="$DIST/share/cp2k/data" ./tests/do_regtest.py \
        --mpiexec "mpiexec --bind-to none" --maxtasks 4 --smoketest \
        --workbasedir /mnt/scratch/regtest "$@" "$DIST/bin" psmp
else
    echo "Skipping CP2K regression execution for the $cp2k_variant build."
fi
popd

# Locks are kept alongside the installed data for later provenance checks.
cp /mnt/scratch/dist/*-explicit.txt "$DIST/share/cp2k/"

printf 'Built libraries:\n'
ldd "$DIST/bin/cp2k.psmp"
