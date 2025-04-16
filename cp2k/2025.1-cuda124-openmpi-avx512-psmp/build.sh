#!/bin/bash
set -e
cd $(dirname $0)

# print system info
id -a
df -h
mount
env

# build
sudo mkdir -p /mnt/share
sudo chmod 777 /mnt/share

docker run --rm \
    -v /mnt/share:/mnt/share:rw \
    -v $(pwd):/mnt/scripts \
    nvidia/cuda:12.4.1-devel-ubuntu22.04 /mnt/scripts/cp2k-build.sh
df -h

# install
TAG=cp2k:2025.1-cuda124-openmpi-avx512-psmp
docker build --build-context dist=/mnt/share/dist --progress plain -t $TAG .

# test
docker run --rm -it $TAG bash <<EOF
source /opt/cp2k/tools/toolchain/install/setup
/opt/cp2k/tests/do_regtest.py --mpiexec "mpiexec --bind-to none" --maxtasks 4 --workbasedir /mnt $* /opt/cp2k/exe/local psmp
EOF


# if environment variable PUBLISH is set to 1, publish the image
if [ "$PUBLISH" == "1" ]; then
    docker tag $TAG $DOCKER_REPO/$TAG
    docker push $DOCKER_REPO/$TAG
fi