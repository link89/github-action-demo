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
docker build . --build-context dist=/mnt/share/dist --progress plain --tag $TAG \
    --label "runnumber=${GITHUB_RUN_ID}"

# publish
# https://docs.github.com/en/packages/managing-github-packages-using-github-actions-workflows/publishing-and-installing-a-package-with-github-actions

IMAGE_URL=ghcr.io/link89/$TAG
echo "$GITHUB_TOKEN" | docker login ghcr.io -u link89 --password-stdin
docker tag $TAG $IMAGE_URL
docker push $IMAGE_URL

# test
docker run --rm -i $TAG bash <<EOF || true
env
source /opt/cp2k/tools/toolchain/install/setup
env
/opt/cp2k/tests/do_regtest.py --mpiexec "mpiexec --bind-to none" --maxtasks 4 --workbasedir /mnt $* /opt/cp2k/exe/local psmp
EOF