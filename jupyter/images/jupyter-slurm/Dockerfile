# JupyterLab dev image: PyTorch + CUDA for quick local GPU tests, plus a thin
# Slurm client that submits to the cluster's login node over SSH.
#
# Why SSH instead of a local slurm client + munge?
#   The login node already runs the exact-version Slurm client and holds cluster
#   auth. Shelling commands to it over SSH is version-proof and avoids syncing
#   munge keys across namespaces. The notebook and the cluster share /home over
#   NFS, so a script you save in Jupyter is submittable by path unchanged.
#
# Build + push (see Makefile target `jupyter-image`):
#   docker build -t $AR/jupyter-slurm:latest jupyter/images/jupyter-slurm
#   docker push  $AR/jupyter-slurm:latest
FROM quay.io/jupyter/pytorch-notebook:cuda12-latest

USER root

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openssh-client \
 && rm -rf /var/lib/apt/lists/*

# Thin wrappers: `sbatch foo.sh`, `squeue`, etc. run on the Slurm login node.
# Configurable via env: SLURM_LOGIN_HOST / SLURM_LOGIN_USER / SLURM_LOGIN_PORT /
# SLURM_SSH_KEY (defaults target the login Service in the `slurm` namespace).
# One dispatcher script; each command name is a symlink that dispatches itself.
RUN set -eux; \
    mkdir -p /opt/slurm-remote/bin; \
    { \
      echo '#!/usr/bin/env bash'; \
      echo 'cmd=$(basename "$0")'; \
      echo 'exec ssh -q -o StrictHostKeyChecking=accept-new \'; \
      echo '  -i "${SLURM_SSH_KEY:-/etc/slurm-ssh/id_ed25519}" \'; \
      echo '  -p "${SLURM_LOGIN_PORT:-22}" \'; \
      echo '  "${SLURM_LOGIN_USER:-root}@${SLURM_LOGIN_HOST:-slurm-login-slinky.slurm.svc.cluster.local}" \'; \
      echo '  -- "$cmd" "$@"'; \
    } > /opt/slurm-remote/slurm-ssh; \
    chmod 0755 /opt/slurm-remote/slurm-ssh; \
    for cmd in sbatch srun salloc squeue scancel scontrol sacct sinfo sstat sacctmgr sprio; do \
      ln -sf /opt/slurm-remote/slurm-ssh /opt/slurm-remote/bin/$cmd; \
    done

ENV PATH=/opt/slurm-remote/bin:${PATH}

USER ${NB_UID}
