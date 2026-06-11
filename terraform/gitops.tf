###############################################################################
# GitOps: Terraform renders every dynamic manifest into ../gitops, installs
# Argo CD, and you commit + apply the root app. Argo then reconciles the rest.
###############################################################################

locals {
  ar_repo      = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
  gpu_gres     = "gpu:${replace(replace(var.gpu_accelerator_type, "nvidia-", ""), "-141gb", "")}:${var.gpu_per_node}"
  filestore_ip = var.filestore_enabled ? google_filestore_instance.shared[0].networks[0].ip_addresses[0] : ""
  gitops_dir   = "${path.module}/../gitops"
}

# --- Rendered Helm values (used by BOTH the Argo path and the Helm-first path)

resource "local_file" "slurm_values" {
  filename = "${local.gitops_dir}/rendered/slurm-values.yaml"
  content = templatefile("${path.module}/templates/slurm-values.yaml.tftpl", {
    SLURMD_IMAGE_REPO    = "${local.ar_repo}/slurmd-cuda"
    SLURMD_IMAGE_TAG     = var.slurmd_image_tag
    GPU_ACCELERATOR      = var.gpu_accelerator_type
    GPU_GRES             = local.gpu_gres
    GPU_NODESET_REPLICAS = var.gpu_nodeset_replicas
    FILESTORE_IP         = local.filestore_ip
  })
}

resource "local_file" "jupyter_values" {
  filename = "${local.gitops_dir}/rendered/jupyter-values.yaml"
  content = templatefile("${path.module}/templates/jupyter-values.yaml.tftpl", {
    JUPYTER_IMAGE_REPO     = "${local.ar_repo}/jupyter-slurm"
    JUPYTER_IMAGE_TAG      = var.jupyter_image_tag
    FILESTORE_IP           = local.filestore_ip
    JUPYTER_DUMMY_PASSWORD = var.jupyter_dummy_password
    GPU_ACCELERATOR        = var.gpu_accelerator_type
  })
}

resource "local_file" "network_objects" {
  filename = "${local.gitops_dir}/fabric/gke-network-objects.yaml"
  content = templatefile("${path.module}/templates/gke-network-objects.yaml.tftpl", {
    GVNIC_NETWORK_PREFIX = var.gvnic_network_prefix
    RDMA_NETWORK_PREFIX  = var.rdma_network_prefix
  })
}

# --- Argo CD manifests (gated by enable_argocd)

resource "local_file" "argocd_project" {
  count    = var.enable_argocd ? 1 : 0
  filename = "${local.gitops_dir}/bootstrap/project.yaml"
  content = templatefile("${path.module}/templates/argocd-project.yaml.tftpl", {
    gitops_repo_url = var.gitops_repo_url
  })
}

resource "local_file" "argocd_appset" {
  count    = var.enable_argocd ? 1 : 0
  filename = "${local.gitops_dir}/bootstrap/appset.yaml"
  content = templatefile("${path.module}/templates/argocd-appset.yaml.tftpl", {
    gitops_repo_url      = var.gitops_repo_url
    gitops_repo_revision = var.gitops_repo_revision
  })
}

resource "local_file" "argocd_fabric_app" {
  count    = var.enable_argocd ? 1 : 0
  filename = "${local.gitops_dir}/bootstrap/fabric-app.yaml"
  content = templatefile("${path.module}/templates/argocd-fabric-app.yaml.tftpl", {
    gitops_repo_url      = var.gitops_repo_url
    gitops_repo_revision = var.gitops_repo_revision
  })
}

resource "local_file" "argocd_root_app" {
  count    = var.enable_argocd ? 1 : 0
  filename = "${local.gitops_dir}/root-app.yaml"
  content = templatefile("${path.module}/templates/argocd-root-app.yaml.tftpl", {
    gitops_repo_url      = var.gitops_repo_url
    gitops_repo_revision = var.gitops_repo_revision
  })
}

# --- Install Argo CD itself (Terraform bootstraps the GitOps engine)

resource "helm_release" "argocd" {
  count            = var.enable_argocd ? 1 : 0
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true

  values = [yamlencode({
    # Keep all Argo components on the CPU/system pool.
    global = {
      nodeSelector = {
        "kubernetes.io/os" = "linux"
        "ml-pool"          = "system"
      }
    }
    configs = {
      # OCI Helm registries MUST be registered with enableOCI for Argo to pull
      # charts from them (repoURL in Applications is then the bare host/path,
      # no oci:// scheme). HTTP helm repos need no registration but listing
      # the public git repo here keeps everything declarative in one place.
      repositories = {
        ghcr-slinky = {
          name      = "slinky"
          type      = "helm"
          url       = "ghcr.io/slinkyproject/charts"
          enableOCI = "true"
        }
        quay-jetstack = {
          name      = "jetstack"
          type      = "helm"
          url       = "quay.io/jetstack/charts"
          enableOCI = "true"
        }
        jupyterhub = {
          name = "jupyterhub"
          type = "helm"
          url  = "https://hub.jupyter.org/helm-chart/"
        }
        gitops = {
          # Public repo needs no credentials; for a PRIVATE repo add
          # username/password (PAT) or sshPrivateKey to this entry.
          type = "git"
          url  = var.gitops_repo_url
        }
      }
    }
  })]

  depends_on = [google_container_node_pool.system]
}

output "gitops_bootstrap_command" {
  value       = var.enable_argocd ? "git add gitops && git commit -m 'gitops values' && git push && kubectl apply -f gitops/root-app.yaml" : "Argo disabled (enable_argocd=false)"
  description = "After `terraform apply`: commit the rendered gitops/ and apply the root app."
}

output "argocd_admin_password_command" {
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  description = "Fetch the initial Argo CD admin password."
}
