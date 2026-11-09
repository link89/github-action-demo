#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

NAME=cp2k
VERSION=2026.2
BUILD_STRING=dp320-cu129-omp-avx512
DOCKER_TAG="${NAME}:${VERSION}-${BUILD_STRING}"
OWNER="${GITHUB_REPOSITORY_OWNER:-link89}"
IMAGE_URL="ghcr.io/${OWNER,,}/${DOCKER_TAG}"
SCRATCH="/mnt/scratch/${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
REVISION="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || true)}"

printf 'Project: %s\nVersion: %s\nBuild string: %s\nImage: %s\nSource: %s\nRevision: %s\nPublish: %s\nScratch: %s\n' \
    "$NAME" "$VERSION" "$BUILD_STRING" "$IMAGE_URL" \
    "${GITHUB_REPOSITORY:-link89/github-action-demo}" "${REVISION:-unknown}" \
    "${PUBLISH:-0}" "$SCRATCH"
printf '\nBuild node\n'
printf 'Host: %s\nKernel: %s\nArchitecture: %s\nCPU cores: %s\nCPU model: %s\n' \
    "$(hostname)" "$(uname -sr)" "$(uname -m)" "$(nproc)" \
    "$(awk -F: '/^model name/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' /proc/cpuinfo)"
(. /etc/os-release; printf 'OS: %s\n' "$PRETTY_NAME")
free -h
df -h / /mnt
findmnt -T /mnt -o TARGET,SOURCE,FSTYPE -n
docker --version
docker info --format 'Docker root: {{.DockerRootDir}}; storage driver: {{.Driver}}'

if [[ "${PUBLISH:-}" == 1 ]]; then
    : "${GITHUB_TOKEN:?GITHUB_TOKEN is required for publishing}"
    echo "$GITHUB_TOKEN" | docker login ghcr.io -u "${GITHUB_ACTOR:-$OWNER}" --password-stdin
fi

if docker manifest inspect "$IMAGE_URL" >/dev/null 2>&1; then
    echo "Already published: $IMAGE_URL"
    exit 0
fi

sudo mkdir -p "$SCRATCH"
sudo chown "$(id -u):$(id -g)" "$SCRATCH"
docker run --rm \
    -e CC=gcc -e CXX=g++ -e FC=gfortran -e F77=gfortran -e F90=gfortran \
    -e OMPI_CC=gcc -e OMPI_CXX=g++ -e OMPI_FC=gfortran \
    -e SOURCE_COMMIT="$REVISION" \
    --mount "type=bind,source=$SCRATCH,target=/mnt/scratch" \
    --mount "type=bind,source=$PWD,target=/mnt/scripts,readonly" \
    nvidia/cuda:12.9.1-cudnn-devel-ubuntu22.04 /mnt/scripts/build-cp2k.sh "$@"

df -h / "$SCRATCH"
docker build . --build-context "dist=$SCRATCH/dist" --progress plain --tag "$DOCKER_TAG" \
    --label "org.opencontainers.image.title=$NAME" \
    --label "org.opencontainers.image.version=$VERSION" \
    --label "org.opencontainers.image.ref.name=$IMAGE_URL" \
    --label "org.opencontainers.image.source=https://github.com/${GITHUB_REPOSITORY:-link89/github-action-demo}" \
    --label "org.opencontainers.image.revision=${REVISION:-unknown}"
docker run --rm --mount "type=bind,source=$PWD,target=/mnt/scripts,readonly" \
    "$DOCKER_TAG" /mnt/scripts/verify-runtime.sh

if [[ "${PUBLISH:-}" == 1 ]]; then
    docker tag "$DOCKER_TAG" "$IMAGE_URL"
    docker push "$IMAGE_URL"
fi
