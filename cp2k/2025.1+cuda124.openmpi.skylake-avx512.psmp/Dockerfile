FROM nvidia/cuda:12.4.1-devel-ubuntu22.04 AS build

RUN --mount=type=bind,target=/mnt/scripts <<EOF
/mnt/scripts/dev-setup.sh
/mnt/scripts/build-cp2k.sh
EOF

FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04 AS install

# Install CP2K binaries
COPY --from=build /opt/cp2k/exe/local/ /opt/cp2k/exe/local/
# Install CP2K regression tests
COPY --from=build /opt/cp2k/tests/ /opt/cp2k/tests/
COPY --from=build /opt/cp2k/tools/regtesting/ /opt/cp2k/tools/regtesting/
COPY --from=build /opt/cp2k/src/grid/sample_tasks/ /opt/cp2k/src/grid/sample_tasks/

# Install CP2K database files
COPY --from=build /opt/cp2k/data/ /opt/cp2k/data/

# Install shared libraries required by the CP2K binaries
COPY --from=build /toolchain/ /opt/cp2k/tools/toolchain/

RUN --mount=type=bind,target=/mnt/scripts <<EOF
/mnt/scripts/dev-setup.sh
/mnt/scripts/install-cp2k.sh
EOF

ENV OMPI_ALLOW_RUN_AS_ROOT=1
ENV OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
ENV OMPI_MCA_btl_vader_single_copy_mechanism=none
ENV OMP_STACKSIZE=16M
ENV PATH=/opt/cp2k/exe/local:$PATH


