output "project_id" {
  value       = var.project_id
  description = "GCP project ID."
}

output "region" {
  value       = var.region
  description = "Cluster region."
}

output "zone" {
  value       = var.zone
  description = "GPU node pool zone."
}

output "gvnic_network_prefix" {
  value       = var.gvnic_network_prefix
  description = "gVNIC VPC name prefix (for the GKE Network objects)."
}

output "rdma_network_prefix" {
  value       = var.rdma_network_prefix
  description = "RDMA VPC name prefix (for the GKE Network objects)."
}

output "gpu_gres" {
  value       = "gpu:${replace(replace(var.gpu_accelerator_type, "nvidia-", ""), "-141gb", "")}:${var.gpu_per_node}"
  description = "Slurm GRES string for the GPU NodeSet (e.g. gpu:h200:8)."
}

output "cluster_name" {
  value       = google_container_cluster.main.name
  description = "GKE cluster name."
}

output "cluster_location" {
  value       = google_container_cluster.main.location
  description = "GKE cluster region."
}

output "get_credentials_command" {
  value       = "gcloud container clusters get-credentials ${google_container_cluster.main.name} --location ${google_container_cluster.main.location} --project ${var.project_id}"
  description = "Run this to point kubectl at the new cluster."
}

output "artifact_registry_repo" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
  description = "Docker image prefix for slurmd / jupyter images."
}

output "gpu_pool_accelerator" {
  value       = var.gpu_accelerator_type
  description = "GPU accelerator label used in nodeSelectors (cloud.google.com/gke-accelerator)."
}

output "filestore_ip" {
  value       = var.filestore_enabled ? google_filestore_instance.shared[0].networks[0].ip_addresses[0] : ""
  description = "Filestore NFS IP to set as nfs.server in the Helm values."
}

output "filestore_share" {
  value       = var.filestore_enabled ? "shared" : ""
  description = "Filestore share/export name (nfs path is /shared)."
}
