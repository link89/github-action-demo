FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04


RUN --mount=type=bind,target=/mnt/scripts <<EOF
/mnt/scripts/dev-setup.sh
/mnt/scripts/cp2k-install.sh
EOF

ENV OMPI_ALLOW_RUN_AS_ROOT=1
ENV OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
ENV OMPI_MCA_btl_vader_single_copy_mechanism=none
ENV OMP_STACKSIZE=16M
ENV PATH=/opt/cp2k/exe/local:$PATH
