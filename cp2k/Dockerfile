ARG BASE_IMAGE=condaforge/miniforge3:26.3.2-3
FROM ${BASE_IMAGE}

COPY --from=dist /runtime-explicit.txt /tmp/runtime-explicit.txt

RUN --mount=type=bind,target=/mnt/scripts <<EOF
/mnt/scripts/install-runtime-deps.sh
EOF

COPY --from=dist /usr/local/ /usr/local/

RUN --mount=type=bind,target=/mnt/scripts <<EOF
/mnt/scripts/install-cp2k.sh
ldconfig
EOF

ENV PATH=/usr/local/bin:${PATH}
ENV PYTHONNOUSERSITE=1
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV NVIDIA_REQUIRE_CUDA="cuda>=12.9"
ENV OMPI_ALLOW_RUN_AS_ROOT=1
ENV OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
ENV OMPI_MCA_btl_vader_single_copy_mechanism=none
ENV OMP_STACKSIZE=16M
ENV CP2K_DATA_DIR=/usr/local/share/cp2k/data

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["cp2k", "--help"]
