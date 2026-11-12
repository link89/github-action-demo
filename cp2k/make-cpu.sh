#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

export BUILD_VARIANT=dp261112b0d8-ompi50x-icelake
export VARIANT_SLUG=cpu
export CP2K_ENABLE_CUDA=0

exec ./build-image.sh "$@"
