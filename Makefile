SHELL := /bin/bash
.DEFAULT_GOAL := help

TF := terraform -chdir=terraform

# --- Resolved from terraform outputs (empty until `make infra` has run) -------
PROJECT_ID           ?= $(shell $(TF) output -raw project_id 2>/dev/null)
REGION               ?= $(shell $(TF) output -raw region 2>/dev/null)
ZONE                 ?= $(shell $(TF) output -raw zone 2>/dev/null)
CLUSTER_NAME         ?= $(shell $(TF) output -raw cluster_name 2>/dev/null)
AR                   ?= $(shell $(TF) output -raw artifact_registry_repo 2>/dev/null)
FILESTORE_IP         ?= $(shell $(TF) output -raw filestore_ip 2>/dev/null)
GVNIC_NETWORK_PREFIX ?= $(shell $(TF) output -raw gvnic_network_prefix 2>/dev/null)
RDMA_NETWORK_PREFIX  ?= $(shell $(TF) output -raw rdma_network_prefix 2>/dev/null)
GPU_ACCELERATOR      ?= $(shell $(TF) output -raw gpu_pool_accelerator 2>/dev/null)
GPU_GRES             ?= $(shell $(TF) output -raw gpu_gres 2>/dev/null)

# --- Tunables -----------------------------------------------------------------
SLURMD_IMAGE_REPO      ?= $(AR)/slurmd-cuda
SLURMD_IMAGE_TAG       ?= 25.11
JUPYTER_IMAGE_REPO     ?= $(AR)/jupyter-slurm
JUPYTER_IMAGE_TAG      ?= latest
GPU_NODESET_REPLICAS   ?= 2
JUPYTER_DUMMY_PASSWORD ?= changeme
GIT_REPO_URL           ?=

NCCL_INSTALLER := https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/refs/heads/master/gpudirect-rdma/nccl-rdma-installer.yaml
JOBSET_MANIFEST := https://github.com/kubernetes-sigs/jobset/releases/latest/download/manifests.yaml

.PHONY: help infra creds images slurmd-image jupyter-image render bootstrap \
        slurm jupyter-ssh-key jupyter nccl-test observability argocd-render all destroy

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

## ----------------------------------------------------------------------------
## Phase 1: infrastructure
## ----------------------------------------------------------------------------
infra: ## terraform init + apply (GKE cluster, RDMA VPCs, pools, Filestore)
	$(TF) init
	$(TF) apply

creds: ## Point kubectl at the new cluster
	gcloud container clusters get-credentials $(CLUSTER_NAME) --location $(REGION) --project $(PROJECT_ID)

## ----------------------------------------------------------------------------
## Phase 2: images
## ----------------------------------------------------------------------------
slurmd-image: ## Build + push the slurmd CUDA image
	gcloud auth configure-docker $(REGION)-docker.pkg.dev -q
	docker build -t $(SLURMD_IMAGE_REPO):$(SLURMD_IMAGE_TAG) slurm/images/slurmd-cuda
	docker push $(SLURMD_IMAGE_REPO):$(SLURMD_IMAGE_TAG)

jupyter-image: ## Build + push the JupyterLab image
	gcloud auth configure-docker $(REGION)-docker.pkg.dev -q
	docker build -t $(JUPYTER_IMAGE_REPO):$(JUPYTER_IMAGE_TAG) jupyter/images/jupyter-slurm
	docker push $(JUPYTER_IMAGE_REPO):$(JUPYTER_IMAGE_TAG)

images: slurmd-image jupyter-image ## Build + push both images

## ----------------------------------------------------------------------------
## Phase 3: render templated values from terraform outputs
## ----------------------------------------------------------------------------
render: ## Render *.tmpl -> concrete YAML (slurm/jupyter values, network objects)
	@test -n "$(FILESTORE_IP)" || { echo "FILESTORE_IP is empty; run 'make infra' first."; exit 1; }
	@GVNIC_NETWORK_PREFIX="$(GVNIC_NETWORK_PREFIX)" RDMA_NETWORK_PREFIX="$(RDMA_NETWORK_PREFIX)" \
	  envsubst '$$GVNIC_NETWORK_PREFIX $$RDMA_NETWORK_PREFIX' \
	  < bootstrap/gke-network-objects.yaml.tmpl > bootstrap/gke-network-objects.yaml
	@SLURMD_IMAGE_REPO="$(SLURMD_IMAGE_REPO)" SLURMD_IMAGE_TAG="$(SLURMD_IMAGE_TAG)" \
	  GPU_ACCELERATOR="$(GPU_ACCELERATOR)" GPU_GRES="$(GPU_GRES)" \
	  GPU_NODESET_REPLICAS="$(GPU_NODESET_REPLICAS)" FILESTORE_IP="$(FILESTORE_IP)" \
	  envsubst '$$SLURMD_IMAGE_REPO $$SLURMD_IMAGE_TAG $$GPU_ACCELERATOR $$GPU_GRES $$GPU_NODESET_REPLICAS $$FILESTORE_IP' \
	  < slurm/slurm-values.yaml.tmpl > slurm/slurm-values.yaml
	@JUPYTER_IMAGE_REPO="$(JUPYTER_IMAGE_REPO)" JUPYTER_IMAGE_TAG="$(JUPYTER_IMAGE_TAG)" \
	  FILESTORE_IP="$(FILESTORE_IP)" JUPYTER_DUMMY_PASSWORD="$(JUPYTER_DUMMY_PASSWORD)" \
	  envsubst '$$JUPYTER_IMAGE_REPO $$JUPYTER_IMAGE_TAG $$FILESTORE_IP $$JUPYTER_DUMMY_PASSWORD' \
	  < jupyter/values.yaml.tmpl > jupyter/values.yaml
	@echo "Rendered: bootstrap/gke-network-objects.yaml, slurm/slurm-values.yaml, jupyter/values.yaml"

## ----------------------------------------------------------------------------
## Phase 4: cluster-wide prerequisites
## ----------------------------------------------------------------------------
bootstrap: render ## GKE network objects + NCCL GIB DaemonSet + cert-manager + JobSet
	kubectl apply -f bootstrap/gke-network-objects.yaml
	kubectl apply -f $(NCCL_INSTALLER)
	kubectl apply --server-side -f $(JOBSET_MANIFEST)
	helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
	  -n cert-manager --create-namespace -f bootstrap/cert-manager-values.yaml

## ----------------------------------------------------------------------------
## Phase 5: Slurm (Slinky)
## ----------------------------------------------------------------------------
slurm: render ## Install slurm-operator (+CRDs) and the Slurm cluster
	helm upgrade --install slurm-operator-crds oci://ghcr.io/slinkyproject/charts/slurm-operator-crds \
	  -n slinky --create-namespace
	helm upgrade --install slurm-operator oci://ghcr.io/slinkyproject/charts/slurm-operator \
	  -n slinky --create-namespace -f slurm/operator-values.yaml
	helm upgrade --install slurm oci://ghcr.io/slinkyproject/charts/slurm \
	  -n slurm --create-namespace -f slurm/slurm-values.yaml

## ----------------------------------------------------------------------------
## Phase 6: JupyterLab dev env
## ----------------------------------------------------------------------------
jupyter-ssh-key: ## Generate the notebook->login SSH key + secret (prints public key)
	@mkdir -p .secrets
	@test -f .secrets/id_ed25519 || ssh-keygen -t ed25519 -N "" -f .secrets/id_ed25519 -C jupyter-slurm
	kubectl create namespace slurm --dry-run=client -o yaml | kubectl apply -f -
	kubectl -n slurm create secret generic jupyter-slurm-ssh \
	  --from-file=id_ed25519=.secrets/id_ed25519 --dry-run=client -o yaml | kubectl apply -f -
	@echo "==> Add this public key to slurm/slurm-values.yaml.tmpl loginsets.slinky.rootSshAuthorizedKeys:"
	@cat .secrets/id_ed25519.pub

jupyter: render jupyter-ssh-key ## Deploy JupyterHub (z2jh) in the slurm namespace
	helm repo add jupyterhub https://hub.jupyter.org/helm-chart/ 2>/dev/null || true
	helm repo update jupyterhub
	helm upgrade --install jupyterhub jupyterhub/jupyterhub \
	  -n slurm --create-namespace -f jupyter/values.yaml

## ----------------------------------------------------------------------------
## Validation + observability
## ----------------------------------------------------------------------------
nccl-test: ## Run the 2-node NCCL all-reduce RDMA fabric test (needs 2 GPU nodes)
	kubectl apply --server-side -f $(JOBSET_MANIFEST)
	kubectl apply -f examples/nccl-test.yaml
	@echo "Watch: kubectl logs -f jobs/nccl-allreduce-worker-0"

observability: ## Apply the Slurm PodMonitoring (GPU metrics are managed via DCGM)
	kubectl apply -f observability/podmonitoring-slurm.yaml

## ----------------------------------------------------------------------------
## GitOps (optional) + full pipeline
## ----------------------------------------------------------------------------
argocd-render: ## Bake GIT_REPO_URL into argocd/ manifests (then commit them)
	@test -n "$(GIT_REPO_URL)" || { echo "Set GIT_REPO_URL=https://github.com/you/repo.git"; exit 1; }
	@grep -rl REPLACE_WITH_GIT_REPO_URL argocd | xargs sed -i.bak "s#REPLACE_WITH_GIT_REPO_URL#$(GIT_REPO_URL)#g"
	@find argocd -name '*.bak' -delete
	@echo "argocd/ manifests now point at $(GIT_REPO_URL)"

all: infra creds bootstrap images slurm jupyter observability ## End-to-end bring-up
	@echo "Done. Validate RDMA with 'make nccl-test', then submit examples/sbatch-2node-ddp.sh."

destroy: ## Tear down all infrastructure (DESTRUCTIVE)
	$(TF) destroy
