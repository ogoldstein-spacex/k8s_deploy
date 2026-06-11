provider "google" {
  project = var.project_id
  region  = var.region
}

# google-beta is required for the RoCE network profile on the RDMA VPC and for
# flex-start / queued-provisioning node pool options.
provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Short-lived token for the helm/kubernetes providers to install Argo CD.
data "google_client_config" "default" {}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.main.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.main.master_auth[0].cluster_ca_certificate)
  }
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.main.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.main.master_auth[0].cluster_ca_certificate)
}
