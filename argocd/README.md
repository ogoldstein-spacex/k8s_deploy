# Optional GitOps with Argo CD

The Helm-first `Makefile` flow is enough to run the platform. Use Argo CD when
you want the cluster continuously reconciled from this git repo.

## One-time setup

```bash
# Install Argo CD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Register the OCI Helm registries Argo will pull charts from
argocd repo add ghcr.io/slinkyproject/charts --type helm --enable-oci
argocd repo add quay.io/jetstack/charts      --type helm --enable-oci
# And this git repo (for value files)
argocd repo add https://github.com/you/k8s_deploy.git
```

## Bootstrap the platform

```bash
# 1. Render + commit the templated value files first (Argo reads from git)
make render
git add -A && git commit -m "platform values" && git push

# 2. Point the apps at your repo URL
make argocd-render GIT_REPO_URL=https://github.com/you/k8s_deploy.git
git add -A && git commit -m "argocd repo url" && git push

# 3. Apply the app-of-apps root
GIT_REPO_URL=https://github.com/you/k8s_deploy.git \
  envsubst < argocd/root-app.yaml | kubectl apply -n argocd -f -
```

Argo CD then syncs, in order (sync waves): cert-manager -> slurm-operator-crds
-> slurm-operator -> slurm -> jupyterhub.

Note: the GPU RDMA bootstrap (GKE Network objects + NCCL GIB DaemonSet) and
Terraform infra are intentionally **not** managed by Argo. Run `make infra` and
`make bootstrap` first; Argo manages the in-cluster applications on top.
