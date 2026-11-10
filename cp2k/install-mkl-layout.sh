#!/bin/bash
set -euo pipefail

prefix="${1:-/usr/local}"
mkl_libraries=("$prefix"/lib/libmkl_*.so)
test -e "${mkl_libraries[0]}"

# CP2K and SpFFT only search the Intel installation layout, while conda
# installs MKL directly under PREFIX/lib.
for compat_dir in intel64 intel64_lin; do
    mkdir -p "$prefix/lib/$compat_dir"
    for library in "${mkl_libraries[@]}"; do
        ln -sfn "../$(basename "$library")" \
            "$prefix/lib/$compat_dir/$(basename "$library")"
    done
done
