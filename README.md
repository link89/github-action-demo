# github-action-demo

## CP2K: Miniforge + MKL

`cp2k/make-cpu.sh` and `cp2k/make-cuda.sh` build CP2K 2026.2 and DeePMD-kit
3.2.0 from source on `condaforge/miniforge3:26.3.2-3`. The CPU and CUDA
variants use separate tags:

```text
ghcr.io/link89/cp2k:2026.2-dp320-ompi50x-icelake-1
ghcr.io/link89/cp2k:2026.2-dp320-ompi50x-cu129-icelake-1
```

CUDA 12.9 remains in the CUDA tag because both CP2K and DeePMD are compiled
with CUDA support. The CPU image omits it because its CP2K acceleration mode is
`NONE`. MKL is omitted from both tags because it is an internal BLAS
implementation detail. The OpenMPI 5.0.x series remains visible because it
determines MPI library compatibility for cross-node jobs.

### Dependencies and build layout

- Mamba installs Python 3.12, CUDA 12.9, cuDNN 9, TensorFlow 2.19.1 (CUDA
  12.8 build, compatible with CUDA 12.9), PyTorch/libtorch 2.10 (CUDA 12.9,
  MKL variant), Intel oneAPI MKL 2025.3, Cython, and GCC/G++/GFortran 14.
  Cython comes from conda-forge in the runtime prefix, so both its Python
  module and command are available without pip.
  The compiler toolchain uses the `compilers=1.11.0` metapackage, which selects
  all three GCC 14 compiler wrappers on linux-64. CUDA development and MKL
  development dependencies use the `cuda-toolkit` and `mkl-devel` metapackages.
- cuSPARSELt uses conda-forge's `cusparselt=0.8.1.1` runtime package and
  `cusparselt-dev=0.8.1.1` build package (headers and linker symlink). This
  release provides CUDA 12 builds; newer releases require CUDA 13.
- Only the MKL components of oneAPI are installed, not Intel MPI or Intel
  compilers. OpenMPI and its C/C++/Fortran wrappers come from conda-forge's
  latest 5.0.x packages (`openmpi`, `openmpi-mpicc`, `openmpi-mpicxx`, and
  `openmpi-mpifort`); OpenMPI is no longer built from source.
- CP2K uses LP64 sequential MKL BLAS/LAPACK and MKL ScaLAPACK with OpenMPI
  BLACS. As in upstream's toolchain, MPI-enabled libvdwxc requires standalone
  FFTW; the other auxiliary libraries are still built by the CP2K toolchain.
  Conda installs MKL under `/usr/local/lib`; both the build prefix and final
  image create `/usr/local/lib/intel64{,_lin}` compatibility links because
  CP2K, SpFFT, and the toolchain only search the Intel installation layout.
  The CPU image keeps `CP2K_USE_ACCEL=NONE`. The CUDA image uses
  `CP2K_USE_ACCEL=CUDA`, `--enable-cuda=yes`, CUDA-enabled DBCSR and SPLA, and
  links cuBLAS, cuFFT, CUDA runtime, and the host CUDA driver.
- The CP2K CUDA compiler builds for compute capabilities `80;86;89;90`
  (A100, A40/L40, and H100). The CP2K toolchain and DBCSR use `A100` as their
  single GPU baseline; the same architecture list is passed to CP2K's CMake
  configuration. This is independent of the Ice Lake-SP CPU baseline.
- DeePMD's CMake configuration loads conda-forge's `ProtobufConfig.cmake`
  before TensorFlow and LibTorch discovery. This ensures the complete set of
  `protobuf::` imported targets exists before framework configs can define a
  partial set, avoiding the CI error where `libprotobuf`, `libprotoc`, etc. are
  already defined but `libupb` and the upb generator targets are missing.
- `conda-runtime.txt` and `conda-build.txt` are solved together. The runtime
  dependency closure is exported as an exact URL/checksum lock, so the final
  image installs the same runtime packages without rerunning the solver or
  explicitly adding GCC, CMake, development packages or the full CUDA toolkit.
  Packages transitively required by the frameworks remain, including any
  CUDA compiler tools required by TensorFlow itself. Package tarballs, channel
  indexes, solver caches and root temporary caches are removed in the same
  Docker layer as runtime installation.
- `/usr/local` is a conda prefix bind-mounted from `/mnt/scratch/conda` while
  building. Sources, package cache, toolchain, build trees and staged output
  also live on `/mnt/scratch`. The final `docker build --build-context` consumes
  the staged installation. The runtime prefix is still `/usr/local`; no conda
  activation or custom `LD_LIBRARY_PATH` is needed when running the image.
- CI uploads `runtime-explicit.txt` and `build-explicit.txt`; copies are also
  included in `/usr/local/share/cp2k`. Increment the final build number when
  rebuilding a published tag; existing tags are never overwritten.

TensorFlow 2.17 from the old wheel-based build is not retained: its conda
protobuf/abseil constraints conflict with libtorch 2.10. The reference
`tmp/build-dpa4-ikkem.sh` warns about TensorFlow 2.19 on H100; this new
all-conda combination still needs real GPU/model validation, especially on
H100. CI checks CPU tensor operations, CUDA-enabled package metadata, shared
C++11 ABI, dynamic library resolution, and loading both DeePMD backend plugins;
it does not establish GPU compatibility or model accuracy.

### Run an input file

The build targets Ice Lake-SP using explicit `icelake-server` flags for CP2K
and its toolchain dependencies. Mount the calculation directory read/write;
the entrypoint treats a direct `.inp` argument or a CP2K executable followed
by an `.inp` argument as a CP2K input.

```bash
IMAGE=ghcr.io/link89/cp2k:2026.2-dp320-ompi50x-icelake-1
CUDA_IMAGE=ghcr.io/link89/cp2k:2026.2-dp320-ompi50x-cu129-icelake-1
docker run --rm -v "$PWD:/work" -e OMP_NUM_THREADS=4 "$IMAGE" cp2k.inp
docker run --rm -v "$PWD:/work" -e OMP_NUM_THREADS=4 "$IMAGE" \
  cp2k cp2k.inp
docker run --rm -v "$PWD:/work" -e OMP_NUM_THREADS=4 "$IMAGE" \
  cp2k.psmp cp2k.inp -o cp2k.out
docker run --rm -v "$PWD:/work" -e OMP_NUM_THREADS=2 "$IMAGE" \
  mpiexec --bind-to none -np 4 cp2k -i cp2k.inp -o cp2k.out
docker run --rm "$IMAGE" cp2k.psmp --version
docker run --rm --gpus all -v "$PWD:/work" "$CUDA_IMAGE" cp2k cp2k.inp
```

For the CUDA image or GPU-enabled DeePMD inference, install NVIDIA Container
Toolkit on the host, use a driver compatible with CUDA 12.9, and add
`--gpus all` to `docker run`.
Ordinary commands and CP2K executables without an input file run unchanged,
e.g. `docker run --rm -it "$IMAGE" bash` or `docker run --rm "$IMAGE"
cp2k.psmp`. Without arguments, the container displays CP2K help.

### Build an Apptainer image

`scripts/build-sif.py` uses `skopeo` to download a Docker image into an OCI
layout and `apptainer` to build a SIF. The image argument uses the same form as
a Dockerfile or Compose image reference:

```bash
python3 scripts/build-sif.py \
  ghcr.io/link89/cp2k:2026.2-dp320-ompi50x-icelake-1
```

This creates `cp2k-2026.2-dp320-ompi50x-icelake-1.sif` and reuses
`./tmp-oci` by default. Pass an output path or `--oci-dir` to override them.
The script does not set Apptainer cache or temporary-directory variables; set
them in the environment when the defaults are unsuitable.

### CI validation

PRs only build and test; only pushes to `main` can publish. The CPU and CUDA
variants run as parallel matrix jobs. Both images are checked for missing
libraries, MKL/OpenMPI linkage, framework versions and ABI, backend plugin
loading, and the expected CP2K acceleration mode. AVX-512-capable runners
execute the CPU image's smoke regressions and entrypoint forms. The CUDA image
is compiled and checked for CUDA linkage, but hosted CPU runners have no GPU and
therefore skip CUDA execution. GPU execution must be validated on a machine
with a compatible driver and `--gpus all`.

References:

- <https://github.com/cp2k/cp2k/blob/master/tools/docker/Dockerfile.test_gcc-mkl-psmp>
- <https://github.com/cp2k/cp2k/blob/master/tools/docker/Dockerfile.test_cuda_A40>
- <https://github.com/conda-forge/cp2k-feedstock>
- <https://docs.deepmodeling.com/projects/deepmd/en/v3.2.0/install/install-from-source.html>
