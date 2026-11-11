#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

export BUILD_VARIANT=dp320-ompi50x-cu129-icelake
export VARIANT_SLUG=cuda
export CP2K_ENABLE_CUDA=1
# DBCSR uses the toolchain's single GPU target; CP2K itself is built for all
# listed architectures, including A100, A40/L40, and H100.
export CP2K_GPU_ARCH="${CP2K_GPU_ARCH:-A100}"
export CP2K_CUDA_ARCHITECTURES="${CP2K_CUDA_ARCHITECTURES:-80;86;89;90}"

exec ./build-image.sh "$@"
