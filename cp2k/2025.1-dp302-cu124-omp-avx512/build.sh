#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

NAME=$(basename "$(dirname "$PWD")")
VERSION_BUILD=$(basename "$PWD")
VERSION=${VERSION_BUILD%%-*}
TAG="${NAME}:${VERSION_BUILD}"
OWNER="${GITHUB_REPOSITORY_OWNER:-link89}"
IMAGE_URL="ghcr.io/${OWNER,,}/${TAG}"
SCRATCH="/mnt/scratch/${NAME}/${VERSION_BUILD}/${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"

if [[ "${PUBLISH:-}" == 1 ]]; then
    : "${GITHUB_TOKEN:?GITHUB_TOKEN is required for publishing}"
    echo "$GITHUB_TOKEN" | docker login ghcr.io -u "${GITHUB_ACTOR:-$OWNER}" --password-stdin
fi

# A published tag is immutable; bump version-build before rebuilding it.
if docker manifest inspect "$IMAGE_URL" >/dev/null 2>&1; then
    echo "Already published: $IMAGE_URL"
    exit 0
fi

df -h / /mnt
mount | grep ' /mnt ' || true
sudo mkdir -p "$SCRATCH"
sudo chown "$(id -u):$(id -g)" "$SCRATCH"

docker run --rm \
    --mount "type=bind,source=$SCRATCH,target=/mnt/scratch" \
    --mount "type=bind,source=$PWD,target=/mnt/scripts,readonly" \
    nvidia/cuda:12.4.1-devel-ubuntu22.04 /mnt/scripts/cp2k-build.sh "$@"

df -h / "$SCRATCH"
docker build . --build-context "dist=$SCRATCH/dist" --progress plain --tag "$TAG" \
    --label "org.opencontainers.image.title=$NAME" \
    --label "org.opencontainers.image.version=$VERSION" \
    --label "org.opencontainers.image.ref.name=$IMAGE_URL" \
    --label "org.opencontainers.image.source=https://github.com/${GITHUB_REPOSITORY:-link89/github-action-demo}" \
    --label "org.opencontainers.image.revision=${GITHUB_SHA:-unknown}"

docker run --rm "$TAG" bash -c \
    'test -x /usr/local/bin/cp2k.psmp && ldd /usr/local/bin/cp2k.psmp > /tmp/cp2k-ldd && ! grep -q "not found" /tmp/cp2k-ldd'

if [[ "${PUBLISH:-}" == 1 ]]; then
    docker tag "$TAG" "$IMAGE_URL"
    docker push "$IMAGE_URL"
fi
