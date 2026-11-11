#!/bin/bash
set -euo pipefail

SOURCE=/mnt/scratch/deepmd-kit
ARCHIVE=/mnt/scratch/deepmd-v3.2.0.tar.gz

curl -fL --retry 3 https://github.com/deepmodeling/deepmd-kit/archive/refs/tags/v3.2.0.tar.gz -o "$ARCHIVE"
tar -xzf "$ARCHIVE" -C /mnt/scratch
mv /mnt/scratch/deepmd-kit-3.2.0 "$SOURCE"

# DeepMD's TensorFlow sources relied on device.h leaking through a PUBLIC PCH.
# Keep that PCH private so the broken install interface is not exported, and
# add the direct includes those sources are missing.
DEEPMD_GPU_CMAKE="$SOURCE/source/lib/src/gpu/CMakeLists.txt"
sed -i \
    's/target_precompile_headers(${GPU_LIB_NAME_SUFFIX} PUBLIC \[\["device.h"\]\])/target_precompile_headers(${GPU_LIB_NAME_SUFFIX} PRIVATE [["device.h"]])/' \
    "$DEEPMD_GPU_CMAKE"
grep -Fq \
    'target_precompile_headers(${GPU_LIB_NAME_SUFFIX} PRIVATE [["device.h"]])' \
    "$DEEPMD_GPU_CMAKE"

DEEPMD_API_SRC="$SOURCE/source/api_cc/src"
for source in DataModifierTF.cc DeepTensorTF.cc; do
    sed -i '/^#include "[^"]*TF\.h"$/a #include "device.h"' \
        "$DEEPMD_API_SRC/$source"
    grep -Fq '#include "device.h"' "$DEEPMD_API_SRC/$source"
done

/usr/local/bin/python /mnt/scripts/verify-frameworks.py
TORCH_CMAKE_PREFIX_PATH=$(/usr/local/bin/python -c 'import torch; print(torch.utils.cmake_prefix_path)')

cmake -S "$SOURCE/source" -B /mnt/scratch/deepmd-build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DMPI_C_COMPILER=/usr/local/bin/mpicc \
    -DMPI_CXX_COMPILER=/usr/local/bin/mpicxx \
    -DCMAKE_CXX_FLAGS=-D_GLIBCXX_USE_CXX11_ABI=1 \
    -DCMAKE_PROJECT_INCLUDE=/mnt/scripts/cmake-preload-protobuf.cmake \
    -DBUILD_CPP_IF=ON -DBUILD_PY_IF=OFF \
    -DENABLE_TENSORFLOW=ON -DUSE_TF_PYTHON_LIBS=ON \
    -DENABLE_PYTORCH=ON -DUSE_PT_PYTHON_LIBS=ON \
    -DCMAKE_PREFIX_PATH="$TORCH_CMAKE_PREFIX_PATH;/usr/local" \
    -DUSE_CUDA_TOOLKIT=ON -DCUDAToolkit_ROOT=/usr/local \
    -DCUDNN_ROOT=/usr/local -DCUSPARSELT_ROOT=/usr/local \
    -DCAFFE2_USE_CUDNN=ON -DCAFFE2_USE_CUSPARSELT=ON \
    -DCAFFE2_STATIC_LINK_CUDA=OFF \
    -DCUDA_USE_STATIC_CUDA_RUNTIME=OFF \
    -DCMAKE_CUDA_RUNTIME_LIBRARY=Shared \
    -DCMAKE_INSTALL_RPATH='/usr/local/lib;/usr/local/lib/python3.12/site-packages/torch/lib' \
    -DCMAKE_CUDA_ARCHITECTURES='80;86;89;90' \
    -DOP_CXX_ABI=1
cmake --build /mnt/scratch/deepmd-build --parallel "$(nproc)"
cmake --install /mnt/scratch/deepmd-build
ldconfig

test -f /usr/local/include/deepmd/DeepPot.h
test -e /usr/local/lib/libdeepmd_c.so
