FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

COPY --from=dist /bin/ /usr/local/bin/
COPY --from=dist /lib/ /usr/local/lib/
COPY --from=dist /share/cp2k/ /usr/local/share/cp2k/

RUN --mount=type=bind,target=/mnt/scripts <<EOF
/mnt/scripts/runtime-deps.sh
/mnt/scripts/cp2k-install.sh
ldconfig
EOF

ENV OMPI_ALLOW_RUN_AS_ROOT=1
ENV OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
ENV OMPI_MCA_btl_vader_single_copy_mechanism=none
ENV OMP_STACKSIZE=16M
ENV CP2K_DATA_DIR=/usr/local/share/cp2k/data

COPY --chmod=755 <<EOF /usr/local/bin/entrypoint.sh
#!/bin/bash
ulimit -c 0 -s unlimited
if [[ \$# -eq 0 ]]; then
  exec /bin/bash
fi
exec "\$@"
EOF
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
