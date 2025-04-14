#!/bin/bash
set -e
cd $(dirname $0)

rm -rf /opt/hostedtoolcache
df -h

TAG=cp2k_2025.1_cuda124.openmpi.skylake-avx512.psmp

docker build --progress plain -t $TAG .

# test
docker run --rm -it $TAG bash <<EOF
source /opt/cp2k/tools/toolchain/install/setup
/opt/cp2k/tests/do_regtest.py --mpiexec "mpiexec --bind-to none" --maxtasks 8 --workbasedir /mnt $* /opt/cp2k/exe/local psmp
EOF
