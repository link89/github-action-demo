#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

test -x /usr/local/bin/cp2k.psmp
test -s /usr/local/share/cp2k/data/BASIS_MOLOPT
test -e /usr/local/lib/libcp2k.so
test -e /usr/local/lib/libdeepmd_c.so
test "$(command -v mpiexec)" = /usr/local/bin/mpiexec
mpiexec --version
mpiexec --version | grep -Eq '5\.0\.'
ldd /usr/local/bin/cp2k.psmp | tee /tmp/cp2k-ldd
if grep -q 'not found' /tmp/cp2k-ldd; then
    echo 'CP2K has unresolved libraries' >&2
    exit 1
fi
grep -Eq 'libmkl_(gf_lp64|core|sequential)' /tmp/cp2k-ldd
grep -q 'libmkl_blacs_openmpi_lp64' /tmp/cp2k-ldd
grep -q 'libmkl_scalapack_lp64' /tmp/cp2k-ldd
if grep -Eq 'libopenblas|libmpich|libmkl_blacs_intelmpi' /tmp/cp2k-ldd; then
    echo 'Unexpected math library or MPI implementation' >&2
    exit 1
fi
mpi_library=$(awk '$1 ~ /^libmpi\.so/ {print $3; exit}' /tmp/cp2k-ldd)
if [[ "$mpi_library" != /usr/local/lib/libmpi.so* ]]; then
    echo "CP2K is not using the conda-forge OpenMPI: $mpi_library" >&2
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

/usr/local/bin/python ./verify-frameworks.py
/usr/local/bin/python -c 'import Cython; print(f"Cython {Cython.__version__}")'
test -x /usr/local/bin/cython
/usr/local/bin/python - <<'PY'
import ctypes
for backend in ('tf', 'pt'):
    ctypes.CDLL(f'/usr/local/lib/libdeepmd_backend_{backend}.so')
    print(f'Loaded DeePMD {backend} backend')
PY

if grep -qw avx512f /proc/cpuinfo; then
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    input="$PWD/smoke.inp"
    cd "$work"
    export OMP_NUM_THREADS=1
    cp2k --version
    /usr/local/bin/entrypoint.sh cp2k "$input" -o serial.out
    grep -q 'ENERGY| Total FORCE_EVAL' serial.out
    /usr/local/bin/entrypoint.sh cp2k.psmp --version
    mpiexec --bind-to none --oversubscribe -np 2 cp2k -i "$input" -o mpi.out
    grep -q 'ENERGY| Total FORCE_EVAL' mpi.out
else
    echo 'Skipping CP2K serial/MPI execution: runner lacks AVX-512.'
fi
