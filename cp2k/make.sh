#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

NAME=cp2k
VERSION=2026.2
BUILD_STRING=dp320-tf219-pt210-cu129-mkl2025.3-ompi506-avx512-0
BASE_IMAGE=condaforge/miniforge3:26.3.2-3
DOCKER_TAG="${NAME}:${VERSION}-${BUILD_STRING}"
OWNER="${GITHUB_REPOSITORY_OWNER:-link89}"
IMAGE_URL="ghcr.io/${OWNER,,}/${DOCKER_TAG}"
SCRATCH="/mnt/scratch/${NAME}-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
REVISION="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || true)}"

printf 'Project: %s\nVersion: %s\nBuild string: %s\nImage: %s\nSource: %s\nRevision: %s\nPublish: %s\nScratch: %s\n' \
    "$NAME" "$VERSION" "$BUILD_STRING" "$IMAGE_URL" \
    "${GITHUB_REPOSITORY:-link89/github-action-demo}" "${REVISION:-unknown}" \
    "${PUBLISH:-0}" "$SCRATCH"
printf 'Base image: %s\n' "$BASE_IMAGE"
printf '\nBuild node\n'
printf 'Host: %s\nKernel: %s\nArchitecture: %s\nCPU cores: %s\nCPU model: %s\n' \
    "$(hostname)" "$(uname -sr)" "$(uname -m)" "$(nproc)" \
    "$(awk -F: '/^model name/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' /proc/cpuinfo)"
(. /etc/os-release; printf 'OS: %s\n' "$PRETTY_NAME")
free -h
sudo mkdir -p "$SCRATCH/conda"
sudo chown -R "$(id -u):$(id -g)" "$SCRATCH"
df -h / "$SCRATCH"
findmnt -T "$SCRATCH" -o TARGET,SOURCE,FSTYPE -n
mount | grep -E ' on /(|mnt[^ ]*) ' || true
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

docker run --rm \
    -e SOURCE_COMMIT="$REVISION" \
    --mount "type=bind,source=$SCRATCH,target=/mnt/scratch" \
    --mount "type=bind,source=$SCRATCH/conda,target=/usr/local" \
    --mount "type=bind,source=$PWD,target=/mnt/scripts,readonly" \
    "$BASE_IMAGE" /mnt/scripts/build-cp2k.sh "$@"

df -h / "$SCRATCH"
docker build . --build-context "dist=$SCRATCH/dist" --progress plain --tag "$DOCKER_TAG" \
    --build-arg "BASE_IMAGE=$BASE_IMAGE" \
    --label "org.opencontainers.image.title=$NAME" \
    --label "org.opencontainers.image.version=$VERSION" \
    --label "org.opencontainers.image.ref.name=$IMAGE_URL" \
    --label "org.opencontainers.image.source=https://github.com/${GITHUB_REPOSITORY:-link89/github-action-demo}" \
    --label "org.opencontainers.image.revision=${REVISION:-unknown}"
docker run --rm --mount "type=bind,source=$PWD,target=/mnt/scripts,readonly" \
    "$DOCKER_TAG" /mnt/scripts/verify-runtime.sh
if grep -qw avx512f /proc/cpuinfo; then
    docker run --rm --mount "type=bind,source=$PWD,target=/work,readonly" \
        --workdir /tmp -e OMP_NUM_THREADS=1 "$DOCKER_TAG" /work/smoke.inp -o /tmp/smoke.out
else
    echo 'Skipping CP2K input execution: this runner lacks AVX-512 (runtime linkage checks still run).'
fi

if [[ "${PUBLISH:-}" == 1 ]]; then
    docker tag "$DOCKER_TAG" "$IMAGE_URL"
    docker push "$IMAGE_URL"
fi
