# Custom slurmd image: Slinky's slurmd + PyTorch/CUDA so `srun python train.py`
# works out of the box, plus auto-sourcing of Google's GIB NCCL env for
# GPUDirect-RDMA. The actual NVIDIA driver libs and the GIB plugin are mounted
# from the host at runtime (/usr/local/nvidia, /usr/local/gib) by the NodeSet.
#
# Keep SLURM_TAG aligned with the deployed slurm-operator / slurm chart version:
#   helm show chart oci://ghcr.io/slinkyproject/charts/slurm | grep version
#
# Build + push (see Makefile target `slurmd-image`):
#   docker build -t $AR/slurmd-cuda:25.11 slurm/images/slurmd-cuda
#   docker push  $AR/slurmd-cuda:25.11
ARG SLURM_TAG=25.11-ubuntu24.04
FROM ghcr.io/slinkyproject/slurmd:${SLURM_TAG}

USER root

# Torch build matched to the GPU arch:
#   H200 (Hopper sm_90):  cu124 works well.
#   B200 (Blackwell sm_100): use cu128 + torch >= 2.7.
ARG TORCH_VERSION=2.5.1
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu124

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      python3 python3-pip python3-venv \
      openmpi-bin libopenmpi-dev \
      openssh-client iputils-ping numactl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# PyTorch + common training stack. Driver/NCCL come from the host mounts.
RUN pip3 install --no-cache-dir --break-system-packages \
      torch==${TORCH_VERSION} --index-url ${TORCH_INDEX_URL} \
 && pip3 install --no-cache-dir --break-system-packages \
      numpy "transformers>=4.44" "datasets>=2.20" accelerate

# Auto-configure NCCL for GPUDirect-RDMA inside every job shell. The GIB plugin
# script only exists once the NodeSet mounts /usr/local/gib, hence the guard.
RUN printf '%s\n' \
      'export LD_LIBRARY_PATH=/usr/local/nvidia/lib64:${LD_LIBRARY_PATH}' \
      'export PATH=/usr/local/nvidia/bin:${PATH}' \
      'if [ -f /usr/local/gib/scripts/set_nccl_env.sh ]; then' \
      '  export NCCL_NET=gIB' \
      '  source /usr/local/gib/scripts/set_nccl_env.sh' \
      'fi' \
      > /etc/profile.d/zz-gib-nccl.sh \
 && chmod 0644 /etc/profile.d/zz-gib-nccl.sh

# Do NOT override the base image entrypoint; the slurm-operator manages it.
