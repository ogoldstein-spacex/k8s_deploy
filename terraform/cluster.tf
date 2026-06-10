###############################################################################
# Node service account (least privilege) + Artifact Registry for our images.
###############################################################################

resource "google_service_account" "nodes" {
  account_id   = "${var.name_prefix}-gke-nodes"
  display_name = "GKE node service account for ${var.name_prefix}"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = "${var.name_prefix}-images"
  description   = "Container images for slurmd, jupyter, and helpers."
  format        = "DOCKER"
  depends_on    = [google_project_service.enabled]
}

###############################################################################
# Regional GKE cluster: Dataplane V2, multi-networking, Workload Identity,
# GKE-managed Prometheus. We manage node pools separately (below).
###############################################################################

resource "google_container_cluster" "main" {
  provider = google-beta
  name     = "${var.name_prefix}-gke"
  location = var.region

  # Run a regional control plane (HA) but pin GPU nodes to a single zone later.
  node_locations = [var.zone]

  release_channel {
    channel = var.release_channel
  }
  min_master_version = var.min_master_version != "" ? var.min_master_version : null

  # We only use this default pool to bootstrap; real pools are in node_pools.tf.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.host.id
  subnetwork = google_compute_subnetwork.cluster.id

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Dataplane V2 (eBPF) + multi-networking are prerequisites for GPUDirect-RDMA.
  datapath_provider       = "ADVANCED_DATAPATH"
  enable_multi_networking = true

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # GKE-managed Prometheus + managed NVIDIA DCGM GPU metrics (no exporter to run).
  monitoring_config {
    managed_prometheus {
      enabled = true
    }
    enable_components = ["SYSTEM_COMPONENTS", "DCGM"]
  }

  addons_config {
    gcs_fuse_csi_driver_config {
      enabled = true
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  # Avoid destroying the cluster on minor in-place config drift.
  lifecycle {
    ignore_changes = [node_config]
  }

  depends_on = [google_project_service.enabled]
}
