#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

: "${BUILD_VARIANT:?BUILD_VARIANT is required}"
: "${VARIANT_SLUG:?VARIANT_SLUG is required}"
: "${CP2K_ENABLE_CUDA:?CP2K_ENABLE_CUDA is required}"

case "$CP2K_ENABLE_CUDA" in
    0) ACCELERATION=CPU ;;
    1) ACCELERATION=CUDA ;;
    *)
        echo "CP2K_ENABLE_CUDA must be 0 or 1" >&2
        exit 1
        ;;
esac

CP2K_GPU_ARCH="${CP2K_GPU_ARCH:-A100}"
CP2K_CUDA_ARCHITECTURES="${CP2K_CUDA_ARCHITECTURES:-80;86;89;90}"

NAME=cp2k
VERSION=2026.2
BUILD_ID=1
BUILD_STRING="${BUILD_VARIANT}-${BUILD_ID}"
BASE_IMAGE=condaforge/miniforge3:26.3.2-3
DOCKER_TAG="${NAME}:${VERSION}-${BUILD_STRING}"
OWNER="${GITHUB_REPOSITORY_OWNER:-link89}"
IMAGE_URL="ghcr.io/${OWNER,,}/${DOCKER_TAG}"
STABLE_TAG="${NAME}:${VERSION}-${BUILD_VARIANT}"
STABLE_IMAGE_URL="ghcr.io/${OWNER,,}/${STABLE_TAG}"
SCRATCH="/mnt/scratch/${NAME}-${VARIANT_SLUG}-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
REVISION="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || true)}"

printf 'Project: %s\nVersion: %s\nBuild string: %s\nAcceleration: %s\nImage: %s\nStable image: %s\nSource: %s\nRevision: %s\nPublish: %s\nScratch: %s\n' \
    "$NAME" "$VERSION" "$BUILD_STRING" "$ACCELERATION" "$IMAGE_URL" \
    "$STABLE_IMAGE_URL" "${GITHUB_REPOSITORY:-link89/github-action-demo}" \
    "${REVISION:-unknown}" "${PUBLISH:-0}" "$SCRATCH"
if [[ "$CP2K_ENABLE_CUDA" == 1 ]]; then
    printf 'CUDA toolchain target: %s\nCP2K CUDA architectures: %s\n' \
        "$CP2K_GPU_ARCH" "$CP2K_CUDA_ARCHITECTURES"
fi
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
    -e CP2K_ENABLE_CUDA="$CP2K_ENABLE_CUDA" \
    -e CP2K_GPU_ARCH="$CP2K_GPU_ARCH" \
    -e CP2K_CUDA_ARCHITECTURES="$CP2K_CUDA_ARCHITECTURES" \
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

gpu_args=()
if [[ "$CP2K_ENABLE_CUDA" == 1 ]] &&
    [[ -e /dev/nvidia0 ]] &&
    command -v nvidia-smi >/dev/null 2>&1 &&
    nvidia-smi -L >/dev/null 2>&1; then
    gpu_args=(--gpus all)
fi

docker run --rm "${gpu_args[@]}" \
    --mount "type=bind,source=$PWD,target=/mnt/scripts,readonly" \
    "$DOCKER_TAG" /mnt/scripts/verify-runtime.sh

can_run=0
if grep -qw avx512f /proc/cpuinfo; then
    if [[ "$CP2K_ENABLE_CUDA" == 0 || ${#gpu_args[@]} -gt 0 ]]; then
        can_run=1
    fi
fi
if ((can_run)); then
    docker run --rm "${gpu_args[@]}" \
        --mount "type=bind,source=$PWD,target=/work,readonly" \
        --workdir /tmp -e OMP_NUM_THREADS=1 "$DOCKER_TAG" /work/smoke.inp -o /tmp/smoke.out
else
    echo 'Skipping CP2K input execution: runner lacks AVX-512 or the CUDA variant has no GPU.'
fi

if [[ "${PUBLISH:-}" == 1 ]]; then
    docker tag "$DOCKER_TAG" "$IMAGE_URL"
    docker push "$IMAGE_URL"
    docker tag "$DOCKER_TAG" "$STABLE_IMAGE_URL"
    docker push "$STABLE_IMAGE_URL"
fi
