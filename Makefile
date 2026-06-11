SHELL := /bin/bash
.DEFAULT_GOAL := help

TF := terraform -chdir=terraform

# --- Resolved from terraform outputs (empty until `make infra` has run) -------
PROJECT_ID   ?= $(shell $(TF) output -raw project_id 2>/dev/null)
REGION       ?= $(shell $(TF) output -raw region 2>/dev/null)
CLUSTER_NAME ?= $(shell $(TF) output -raw cluster_name 2>/dev/null)
AR           ?= $(shell $(TF) output -raw artifact_registry_repo 2>/dev/null)

SLURMD_IMAGE_TAG  ?= 25.11
JUPYTER_IMAGE_TAG ?= latest

NCCL_INSTALLER  := https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/refs/heads/master/gpudirect-rdma/nccl-rdma-installer.yaml
JOBSET_MANIFEST := https://github.com/kubernetes-sigs/jobset/releases/latest/download/manifests.yaml

.PHONY: help infra creds images slurmd-image jupyter-image gitops \
        bootstrap slurm jupyter-ssh-key jupyter nccl-test observability all destroy

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

## --- Phase 1: infrastructure (also installs Argo CD + renders gitops/) -------
infra: ## terraform init + apply: GKE, RDMA VPCs, pools, Filestore, Argo CD, gitops render
	$(TF) init
	$(TF) apply

creds: ## Point kubectl at the new cluster
	gcloud container clusters get-credentials $(CLUSTER_NAME) --location $(REGION) --project $(PROJECT_ID)

## --- Phase 2: images ---------------------------------------------------------
slurmd-image: ## Build + push the slurmd CUDA image
	gcloud auth configure-docker $(REGION)-docker.pkg.dev -q
	docker build -t $(AR)/slurmd-cuda:$(SLURMD_IMAGE_TAG) slurm/images/slurmd-cuda
	docker push $(AR)/slurmd-cuda:$(SLURMD_IMAGE_TAG)

jupyter-image: ## Build + push the JupyterLab image
	gcloud auth configure-docker $(REGION)-docker.pkg.dev -q
	docker build -t $(AR)/jupyter-slurm:$(JUPYTER_IMAGE_TAG) jupyter/images/jupyter-slurm
	docker push $(AR)/jupyter-slurm:$(JUPYTER_IMAGE_TAG)

images: slurmd-image jupyter-image ## Build + push both images

## --- Phase 3: GitOps (PRIMARY) ----------------------------------------------
gitops: jupyter-ssh-key ## Commit the TF-rendered gitops/ and apply the Argo root app
	git add gitops
	@git diff --cached --quiet || git commit -m "chore: update gitops rendered manifests"
	git push
	kubectl apply -f gitops/root-app.yaml
	@echo "Argo CD admin password:"; \
	  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
	@echo "UI: kubectl -n argocd port-forward svc/argocd-server 8080:443"

jupyter-ssh-key: ## Generate the notebook->login SSH key + secret (prints public key)
	@mkdir -p .secrets
	@test -f .secrets/id_ed25519 || ssh-keygen -t ed25519 -N "" -f .secrets/id_ed25519 -C jupyter-slurm
	kubectl create namespace slurm --dry-run=client -o yaml | kubectl apply -f -
	kubectl -n slurm create secret generic jupyter-slurm-ssh \
	  --from-file=id_ed25519=.secrets/id_ed25519 --dry-run=client -o yaml | kubectl apply -f -
	@echo "==> Add this key to loginsets.slinky.rootSshAuthorizedKeys in"
	@echo "    terraform/templates/slurm-values.yaml.tftpl, then re-run 'make infra gitops':"
	@cat .secrets/id_ed25519.pub

## --- Validation --------------------------------------------------------------
nccl-test: ## Run the 2-node NCCL all-reduce RDMA fabric test (needs 2 GPU nodes)
	kubectl apply --server-side -f $(JOBSET_MANIFEST)
	kubectl apply -f examples/nccl-test.yaml
	@echo "Watch: kubectl logs -f jobs/nccl-allreduce-worker-0"

observability: ## Apply the Slurm PodMonitoring (GPU metrics are managed via DCGM)
	kubectl apply -f observability/podmonitoring-slurm.yaml

all: infra creds images gitops ## End-to-end: infra+Argo, images, then GitOps sync
	@echo "Argo CD is syncing the platform. Watch: kubectl -n argocd get applications -w"

## --- Helm-first alternative (no Argo; consumes the same TF-rendered values) --
bootstrap: ## [helm-first] GPU fabric + cert-manager + JobSet without Argo
	kubectl apply -k gitops/fabric
	kubectl apply --server-side -f $(JOBSET_MANIFEST)
	helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
	  -n cert-manager --create-namespace -f bootstrap/cert-manager-values.yaml

slurm: ## [helm-first] Install slurm-operator (+CRDs) and the Slurm cluster
	helm upgrade --install slurm-operator-crds oci://ghcr.io/slinkyproject/charts/slurm-operator-crds \
	  -n slinky --create-namespace
	helm upgrade --install slurm-operator oci://ghcr.io/slinkyproject/charts/slurm-operator \
	  -n slinky --create-namespace -f slurm/operator-values.yaml
	helm upgrade --install slurm oci://ghcr.io/slinkyproject/charts/slurm \
	  -n slurm --create-namespace -f gitops/rendered/slurm-values.yaml

jupyter: jupyter-ssh-key ## [helm-first] Deploy JupyterHub (z2jh) in the slurm namespace
	helm repo add jupyterhub https://hub.jupyter.org/helm-chart/ 2>/dev/null || true
	helm repo update jupyterhub
	helm upgrade --install jupyterhub jupyterhub/jupyterhub \
	  -n slurm --create-namespace -f gitops/rendered/jupyter-values.yaml

destroy: ## Tear down all infrastructure (DESTRUCTIVE)
	$(TF) destroy
