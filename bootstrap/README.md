# Bootstrap (cluster-wide prerequisites)

Apply these after `terraform apply` and `gcloud ... get-credentials`, in order.
The `Makefile` target `make bootstrap` runs all of this for you.

## 1. GKE multi-network objects (required for GPUDirect-RDMA)

`gke-network-objects.yaml.tmpl` defines the in-cluster `Network` objects
(`gvnic-1`, `rdma-0..7`) that map onto the VPCs/subnets Terraform created. Pods
that want RDMA reference these by name in the `networking.gke.io/interfaces`
annotation.

Render + apply (the Makefile does this with `envsubst`):

```bash
export GVNIC_NETWORK_PREFIX=a3ultra-gvnic
export RDMA_NETWORK_PREFIX=a3ultra-rdma
envsubst < bootstrap/gke-network-objects.yaml.tmpl | kubectl apply -f -
```

The prefixes must match `gvnic_network_prefix` / `rdma_network_prefix` in your
`terraform.tfvars` (defaults shown above; use `a4high-*` for A4/B200).

## 2. NCCL "GIB" RDMA plugin DaemonSet

Installs the RoCE/RDMA binaries to `/home/kubernetes/bin/gib` and a tuned NCCL
to `/home/kubernetes/bin/nvidia/lib64` on every GPU node. Workloads then mount
those host paths and run `source /usr/local/gib/scripts/set_nccl_env.sh`.

```bash
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/refs/heads/master/gpudirect-rdma/nccl-rdma-installer.yaml
```

(For A3 High / A3 Mega -- TCPX / TCPXO instead of RDMA -- use the
`nccl-tcpx-installer` / `nccl-tcpxo-installer` DaemonSets instead.)

## 3. cert-manager (Slinky prerequisite)

```bash
helm install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --namespace cert-manager --create-namespace \
  -f bootstrap/cert-manager-values.yaml
```

## Validate

Before deploying Slurm, confirm the fabric with the NCCL all-reduce test:

```bash
kubectl apply -f examples/nccl-test.yaml
```

See `examples/` for details.
