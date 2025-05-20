FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

COPY --from=dist . /opt/cp2k/

RUN --mount=type=bind,target=/mnt/scripts <<EOF
/mnt/scripts/dev-setup.sh
/mnt/scripts/cp2k-install.sh
EOF

# Set environment variables
ENV OMPI_ALLOW_RUN_AS_ROOT=1
ENV OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
ENV OMPI_MCA_btl_vader_single_copy_mechanism=none
ENV OMP_STACKSIZE=16M
ENV PATH=/opt/cp2k/exe/local:$PATH
ENV CP2K_DATA_DIR=/opt/cp2k/data
ENV CUDA_HOME=/usr/local/cuda
ENV CUDA_PATH=/usr/local/cuda
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# Create entrypoint script file
COPY --chmod=755 <<EOF /usr/local/bin/entrypoint.sh
#!/bin/bash
ulimit -c 0 -s unlimited
source /opt/cp2k/tools/toolchain/install/setup
if [[ $# -eq 0 ]]; then
  exec "/bin/bash"
else
  exec "$@"
fi
EOF
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
