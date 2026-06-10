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
