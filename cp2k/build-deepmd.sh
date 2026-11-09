#!/bin/bash
set -euo pipefail

SOURCE=/mnt/scratch/deepmd-kit
ARCHIVE=/mnt/scratch/deepmd-v3.2.0.tar.gz

curl -fL --retry 3 https://github.com/deepmodeling/deepmd-kit/archive/refs/tags/v3.2.0.tar.gz -o "$ARCHIVE"
tar -xzf "$ARCHIVE" -C /mnt/scratch
mv /mnt/scratch/deepmd-kit-3.2.0 "$SOURCE"

# DeepMD exports its CUDA device.h PCH to consumers, but installs the header
# under include/deepmd. Keep this implementation detail private to DeepMD.
DEEPMD_GPU_CMAKE="$SOURCE/source/lib/src/gpu/CMakeLists.txt"
sed -i \
    's/target_precompile_headers(${GPU_LIB_NAME_SUFFIX} PUBLIC \[\["device.h"\]\])/target_precompile_headers(${GPU_LIB_NAME_SUFFIX} PRIVATE [["device.h"]])/' \
    "$DEEPMD_GPU_CMAKE"
grep -Fq \
    'target_precompile_headers(${GPU_LIB_NAME_SUFFIX} PRIVATE [["device.h"]])' \
    "$DEEPMD_GPU_CMAKE"

python3 -m pip install --no-cache-dir --target "$PYTHONPATH" \
    --extra-index-url https://download.pytorch.org/whl/cu129 \
    'torch==2.10.0+cu129' 'tensorflow==2.17.0' 'numpy<2'

# Both framework wheels must expose the new libstdc++ C++11 ABI.
python3 - <<'PY'
import tensorflow as tf
import torch

tf_flags = tf.sysconfig.get_compile_flags()
tf_abi = next((flag.split('=')[-1] for flag in tf_flags if '_GLIBCXX_USE_CXX11_ABI=' in flag), None)
torch_abi = int(torch._C._GLIBCXX_USE_CXX11_ABI)
print(f'TensorFlow {tf.__version__}: CXX11 ABI={tf_abi}')
print(f'PyTorch {torch.__version__}: CXX11 ABI={torch_abi}')
if tf.__version__ != '2.17.0' or torch.__version__ != '2.10.0+cu129':
    raise SystemExit('Framework version mismatch')
if tf_abi != '1' or torch_abi != 1:
    raise SystemExit('TensorFlow and PyTorch must both use CXX11 ABI=1')
PY

cmake -S "$SOURCE/source" -B /mnt/scratch/deepmd-build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
    -DMPI_C_COMPILER=/usr/local/bin/mpicc \
    -DMPI_CXX_COMPILER=/usr/local/bin/mpicxx \
    -DCMAKE_CXX_FLAGS=-D_GLIBCXX_USE_CXX11_ABI=1 \
    -DBUILD_CPP_IF=ON -DBUILD_PY_IF=OFF \
    -DENABLE_TENSORFLOW=ON -DUSE_TF_PYTHON_LIBS=ON \
    -DENABLE_PYTORCH=ON -DUSE_PT_PYTHON_LIBS=ON \
    -DUSE_CUDA_TOOLKIT=ON -DCUDAToolkit_ROOT=/usr/local/cuda \
    -DCMAKE_CUDA_ARCHITECTURES='80;86;89;90' \
    -DOP_CXX_ABI=1
cmake --build /mnt/scratch/deepmd-build --parallel "$(nproc)"
cmake --install /mnt/scratch/deepmd-build
ldconfig

test -f /usr/local/include/deepmd/DeepPot.h
test -e /usr/local/lib/libdeepmd_c.so
