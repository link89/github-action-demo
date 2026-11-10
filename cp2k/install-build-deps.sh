#!/bin/bash
set -euo pipefail

export CONDA_OVERRIDE_CUDA=12.9
export CONDA_PKGS_DIRS=/mnt/scratch/conda-pkgs
mkdir -p /mnt/scratch/dist

# Solve the build and runtime together; the runtime lock selects a dependency
# closure from these exact packages, not a second potentially different solve.
mkdir -p /usr/local/conda-meta
touch /usr/local/conda-meta/history
/opt/conda/bin/mamba install -y --prefix /usr/local \
    --override-channels -c conda-forge --strict-channel-priority \
    --file /mnt/scripts/conda-runtime.txt --file /mnt/scripts/conda-build.txt

# Conda installs MKL directly under PREFIX/lib, while CP2K and SpFFT CMake
# finders only search the Intel layout under PREFIX/lib/intel64{,_lin}.
mkl_libraries=(/usr/local/lib/libmkl_*.so)
test -e "${mkl_libraries[0]}"
for compat_dir in intel64 intel64_lin; do
    mkdir -p "/usr/local/lib/$compat_dir"
    for library in "${mkl_libraries[@]}"; do
        ln -sfn "../$(basename "$library")" \
            "/usr/local/lib/$compat_dir/$(basename "$library")"
    done
done

/opt/conda/bin/conda list --prefix /usr/local --explicit \
    > /mnt/scratch/dist/build-explicit.txt
/usr/local/bin/python /mnt/scripts/export-runtime-lock.py \
    /usr/local /mnt/scripts/conda-runtime.txt /mnt/scratch/dist/runtime-explicit.txt
