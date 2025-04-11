FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

# Install packages required for the CP2K toolchain build
RUN apt-get update -qq && apt-get install -qq --no-install-recommends \
    g++ gcc gfortran openssh-client python3 python3-pip \
    bzip2 ca-certificates git make patch pkg-config unzip wget zlib1g-dev

# Install tensorflow
RUN pip3 install tensorflow

# Install libtorch
WORKDIR /opt/libtorch/
RUN wget https://download.pytorch.org/libtorch/cu124/libtorch-cxx11-abi-shared-with-deps-2.6.0%2Bcu124.zip



# Download CP2K
RUN git clone --recursive -b support/v2025.1 https://github.com/cp2k/cp2k.git /opt/cp2k


# Build CP2K toolchain for target CPU skylake-avx512
WORKDIR /opt/cp2k/tools/toolchain
RUN /bin/bash -c -o pipefail \
    "./install_cp2k_toolchain.sh -j 8 \
     --install-all \
     --enable-cuda=no \
     --target-cpu=skylake-avx512 \
     --with-cusolvermp=no \
     --with-libtorch=system \
     --with-deepmd=system \
     --with-gcc=system \
     --with-openmpi=install"

# Build CP2K for target CPU skylake-avx512
WORKDIR /opt/cp2k
RUN /bin/bash -c -o pipefail \
    "cp ./tools/toolchain/install/arch/local.psmp ./arch/; \
     source ./tools/toolchain/install/setup; \
     make -j 8 ARCH=local VERSION=psmp"

# Collect components for installation and remove symbolic links
RUN /bin/bash -c -o pipefail \
    "mkdir -p /toolchain/install /toolchain/scripts; \
     for libdir in \$(ldd ./exe/local/cp2k.psmp | \
                      grep /opt/cp2k/tools/toolchain/install | \
                      awk '{print \$3}' | cut -d/ -f7 | \
                      sort | uniq) setup; do \
        cp -ar /opt/cp2k/tools/toolchain/install/\${libdir} /toolchain/install; \
     done; \
     cp /opt/cp2k/tools/toolchain/scripts/tool_kit.sh /toolchain/scripts; \
     unlink ./exe/local/cp2k.popt; \
     unlink ./exe/local/cp2k_shell.psmp"

