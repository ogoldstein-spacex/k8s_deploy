# Bootstrap values

This directory now only holds static Helm values consumed by both the Argo CD
path and the Helm-first path:

- `cert-manager-values.yaml` - cert-manager config (Slinky prerequisite). The
  Argo `ApplicationSet` references it at `bootstrap/cert-manager-values.yaml`.

The GPU fabric that used to live here (NCCL GIB DaemonSet + GKE Network objects)
is now under `gitops/fabric/`:

- `gitops/fabric/nccl-rdma-installer.yaml` - vendored, pinned NCCL/GIB DaemonSet.
- `gitops/fabric/gke-network-objects.yaml` - rendered by Terraform from
  `terraform/templates/gke-network-objects.yaml.tftpl`.

Argo applies the fabric first (sync wave -1) via `gitops/bootstrap/fabric-app.yaml`.
For the Helm-first path, `make bootstrap` runs `kubectl apply -k gitops/fabric`.
