#!/bin/bash
set -euo pipefail

version=5.0.6
archive="/mnt/scratch/openmpi-${version}.tar.gz"
source_dir="/mnt/scratch/openmpi-${version}"
build_dir=/mnt/scratch/openmpi-build

curl -fL --retry 3 \
    "https://download.open-mpi.org/release/open-mpi/v5.0/openmpi-${version}.tar.gz" \
    -o "$archive"
tar -xzf "$archive" -C /mnt/scratch
mkdir -p "$build_dir"

pushd "$build_dir"
"$source_dir/configure" --prefix=/usr/local --disable-static \
    --with-hwloc=internal --with-libevent=internal --with-pmix=internal
make -j "$(nproc)"
make install
make install DESTDIR=/mnt/scratch/dist
popd

ldconfig
test "$(command -v mpicc)" = /usr/local/bin/mpicc
test -f /usr/local/include/mpi.h
mpicc --showme:compile
mpicc --showme:link
