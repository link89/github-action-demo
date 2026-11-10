"""Check versions, CUDA-enabled builds and the shared C++ ABI without a GPU."""

import sys

import tensorflow as tf
import torch

tf_abi = next(
    (flag.split("=")[-1] for flag in tf.sysconfig.get_compile_flags()
     if "_GLIBCXX_USE_CXX11_ABI=" in flag), None
)
print("Python:", sys.executable, sys.prefix)
print("TensorFlow:", tf.__version__, "CXX11 ABI:", tf_abi)
print("PyTorch:", torch.__version__, "CXX11 ABI:", torch._C._GLIBCXX_USE_CXX11_ABI)
print("TensorFlow CUDA:", tf.sysconfig.get_build_info())
print("PyTorch CUDA:", torch.version.cuda)
assert sys.prefix == "/usr/local"
assert tf.__version__ == "2.19.1"
assert torch.__version__.split("+")[0] == "2.10.0"
assert tf_abi == "1" and torch._C._GLIBCXX_USE_CXX11_ABI
assert tf.test.is_built_with_cuda()
assert torch.version.cuda == "12.9"
with tf.device("/CPU:0"):
    assert float(tf.reduce_sum(tf.ones((2, 2))).numpy()) == 4.0
assert torch.ones((2, 2), device="cpu").sum().item() == 4.0
