#!/bin/bash
set -euo pipefail

test -x /usr/local/bin/cp2k.psmp
test -s /usr/local/share/cp2k/data/BASIS_MOLOPT
test -e /usr/local/lib/libcp2k.so
test -e /usr/local/lib/libdeepmd_c.so
test "$(command -v mpiexec)" = /usr/local/bin/mpiexec
mpiexec --version
ldd /usr/local/bin/cp2k.psmp | tee /tmp/cp2k-ldd
if grep -q 'not found' /tmp/cp2k-ldd; then
    echo 'CP2K has unresolved libraries' >&2
    exit 1
fi
mpi_library=$(awk '$1 ~ /^libmpi\.so/ {print $3; exit}' /tmp/cp2k-ldd)
if [[ "$mpi_library" != /usr/local/lib/libmpi.so* ]]; then
    echo "CP2K is not using the source-built OpenMPI: $mpi_library" >&2
    exit 1
fi
for library in /usr/local/lib/libdeepmd*.so; do
    printf 'Checking %s\n' "$library"
    ldd "$library" | tee /tmp/deepmd-ldd
    if grep -q 'not found' /tmp/deepmd-ldd; then
        echo "Unresolved libraries in $library" >&2
        exit 1
    fi
done
test -e /usr/local/lib/libdeepmd_backend_pt.so
test -e /usr/local/lib/libdeepmd_backend_tf.so

python3 - <<'PY'
import tensorflow as tf
import torch

tf_abi = next((flag.split('=')[-1] for flag in tf.sysconfig.get_compile_flags()
               if '_GLIBCXX_USE_CXX11_ABI=' in flag), None)
print('TensorFlow:', tf.__version__, 'CXX11 ABI:', tf_abi)
print('PyTorch:', torch.__version__, 'CXX11 ABI:', torch._C._GLIBCXX_USE_CXX11_ABI)
assert tf.__version__ == '2.17.0'
assert torch.__version__ == '2.10.0+cu129'
assert tf_abi == '1' and torch._C._GLIBCXX_USE_CXX11_ABI
PY
