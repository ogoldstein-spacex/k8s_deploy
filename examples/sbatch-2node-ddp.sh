#!/bin/bash
# 2-node x 8-GPU PyTorch DDP sanity job over GPUDirect-RDMA, submitted to Slurm.
#
# Usage (from the login pod or a Jupyter terminal that has the Slurm client):
#   sbatch examples/sbatch-2node-ddp.sh
#   squeue
#   tail -f ddp-<jobid>.out
#
# A healthy run prints matching all-reduce results from all 16 ranks and NCCL
# debug lines showing the gIB (RoCE/RDMA) transport in use.
#SBATCH --job-name=ddp-allreduce
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:8
#SBATCH --time=00:15:00
#SBATCH --output=ddp-%j.out

set -euo pipefail

# Tuned NCCL settings for Google RoCE/RDMA (installed by the GIB DaemonSet).
export NCCL_NET=gIB
if [ -f /usr/local/gib/scripts/set_nccl_env.sh ]; then
  source /usr/local/gib/scripts/set_nccl_env.sh
fi
export NCCL_DEBUG=INFO

# torchrun rendezvous: use the first node in the allocation as master.
export MASTER_ADDR="$(scontrol show hostnames "$SLURM_JOB_NODELIST" | head -n1)"
export MASTER_PORT=29500
echo "Master: ${MASTER_ADDR}:${MASTER_PORT}  Nodes: ${SLURM_NNODES}"

cat > /tmp/ddp_allreduce.py <<'PY'
import os
import torch
import torch.distributed as dist

def main():
    dist.init_process_group(backend="nccl")
    rank = dist.get_rank()
    world = dist.get_world_size()
    local_rank = int(os.environ.get("LOCAL_RANK", 0))
    torch.cuda.set_device(local_rank)

    # All-reduce a tensor of each rank's id; sum should equal world*(world-1)/2.
    t = torch.full((1 << 20,), float(rank), device="cuda")
    dist.all_reduce(t, op=dist.ReduceOp.SUM)
    expected = world * (world - 1) / 2
    ok = torch.allclose(t[0].cpu(), torch.tensor(expected))
    print(f"[rank {rank}/{world}] local_rank={local_rank} "
          f"allreduce={t[0].item():.0f} expected={expected:.0f} ok={ok}", flush=True)
    dist.barrier()
    if rank == 0:
        print("DDP all-reduce sanity PASSED" if ok else "FAILED", flush=True)
    dist.destroy_process_group()

if __name__ == "__main__":
    main()
PY

# One torchrun per node (srun --ntasks-per-node=1); each spawns 8 local ranks.
srun --kill-on-bad-exit=1 torchrun \
  --nnodes="${SLURM_NNODES}" \
  --nproc-per-node=8 \
  --rdzv-id="${SLURM_JOB_ID}" \
  --rdzv-backend=c10d \
  --rdzv-endpoint="${MASTER_ADDR}:${MASTER_PORT}" \
  /tmp/ddp_allreduce.py
