FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

# Install CP2K binaries
COPY --from=share ./cp2k/exe/local/ /opt/cp2k/exe/local/
# Install CP2K regression tests
COPY --from=share ./cp2k/tests/ /opt/cp2k/tests/
COPY --from=share ./cp2k/tools/regtesting/ /opt/cp2k/tools/regtesting/
COPY --from=share ./cp2k/src/grid/sample_tasks/ /opt/cp2k/src/grid/sample_tasks/

# Install CP2K database files
COPY --from=share ./cp2k/data/ /opt/cp2k/data/

# Install shared libraries required by the CP2K binaries
COPY --from=share ./toolchain/ /opt/cp2k/tools/toolchain/

RUN --mount=type=bind,target=/mnt/scripts <<EOF
/mnt/scripts/dev-setup.sh
/mnt/scripts/cp2k-install.sh
EOF

ENV OMPI_ALLOW_RUN_AS_ROOT=1
ENV OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
ENV OMPI_MCA_btl_vader_single_copy_mechanism=none
ENV OMP_STACKSIZE=16M
ENV PATH=/opt/cp2k/exe/local:$PATH
