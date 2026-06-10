locals {
  gpu_use_reservation = var.gpu_capacity_mode == "reservation"
  gpu_use_flex_start  = var.gpu_capacity_mode == "flex_start"
  gpu_use_spot        = var.gpu_capacity_mode == "spot"

  # Order matters: gVNIC becomes eth1, rdma-0..7 become eth2..eth9. The Pod
  # `networking.gke.io/interfaces` annotation must match this ordering.
  gpu_additional_networks = concat(
    [{
      network    = google_compute_network.gvnic.name
      subnetwork = google_compute_subnetwork.gvnic.name
    }],
    [for s in google_compute_subnetwork.rdma : {
      network    = google_compute_network.rdma.name
      subnetwork = s.name
    }]
  )
}

###############################################################################
# System pool: operators, slurmctld, jupyterhub, cert-manager, exporters.
###############################################################################

resource "google_container_node_pool" "system" {
  name     = "system"
  cluster  = google_container_cluster.main.id
  location = var.region

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = "e2-standard-8"
    disk_size_gb    = 100
    disk_type       = "pd-balanced"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = { "ml-pool" = "system" }

    gvnic {
      enabled = true
    }
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}

###############################################################################
# Dev pool: cheap L4 GPUs for JupyterLab quick tests. Scales to zero.
###############################################################################

resource "google_container_node_pool" "dev_l4" {
  name     = "dev-l4"
  cluster  = google_container_cluster.main.id
  location = var.region

  autoscaling {
    total_min_node_count = 0
    total_max_node_count = var.dev_max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.dev_machine_type
    disk_size_gb    = 200
    disk_type       = "pd-balanced"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = { "ml-pool" = "dev-l4" }

    guest_accelerator {
      type  = var.dev_accelerator_type
      count = var.dev_gpu_per_node
      gpu_driver_installation_config {
        gpu_driver_version = "LATEST"
      }
    }

    gvnic {
      enabled = true
    }
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}

###############################################################################
# GPU training pool: A3 Ultra (H200) / A4 (B200) with GPUDirect-RDMA.
# Single zone, gVNIC + 8 RDMA NICs, TIER_1 bandwidth, GKE-managed driver.
###############################################################################

resource "google_container_node_pool" "gpu" {
  provider = google-beta
  name     = "gpu-rdma"
  cluster  = google_container_cluster.main.id
  location = var.region

  # GPUDirect-RDMA node pools must be single-zone.
  node_locations = [var.zone]

  autoscaling {
    total_min_node_count = var.gpu_min_nodes
    total_max_node_count = var.gpu_max_nodes
    location_policy      = local.gpu_use_flex_start ? "ANY" : "BALANCED"
  }

  management {
    # Flex-start nodes are short-lived and must not be auto-repaired.
    auto_repair  = local.gpu_use_flex_start ? false : true
    auto_upgrade = false
  }

  dynamic "queued_provisioning" {
    for_each = local.gpu_use_flex_start ? [1] : []
    content {
      enabled = true
    }
  }

  upgrade_settings {
    strategy = local.gpu_use_flex_start ? "SHORT_LIVED" : "SURGE"
  }

  node_config {
    machine_type    = var.gpu_machine_type
    image_type      = "COS_CONTAINERD" # required for GPUDirect-RDMA
    disk_size_gb    = 500
    disk_type       = "pd-ssd"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = {
      "ml-pool" = "gpu-rdma"
    }

    spot       = local.gpu_use_spot
    flex_start = local.gpu_use_flex_start

    guest_accelerator {
      type  = var.gpu_accelerator_type
      count = var.gpu_per_node
      gpu_driver_installation_config {
        gpu_driver_version = var.gpu_driver_version
      }
    }

    gvnic {
      enabled = true
    }

    # Full line-rate egress for collective communication.
    dynamic "reservation_affinity" {
      for_each = local.gpu_use_reservation ? [1] : (local.gpu_use_flex_start ? [1] : [])
      content {
        consume_reservation_type = local.gpu_use_reservation ? "SPECIFIC_RESERVATION" : "NO_RESERVATION"
        key                      = local.gpu_use_reservation ? "compute.googleapis.com/reservation-name" : null
        values                   = local.gpu_use_reservation ? [var.reservation_name] : null
      }
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  network_config {
    # TIER_1 bandwidth is required to reach advertised GPUDirect throughput.
    network_performance_config {
      total_egress_bandwidth_tier = "TIER_1"
    }

    dynamic "additional_node_network_configs" {
      for_each = local.gpu_additional_networks
      content {
        network    = additional_node_network_configs.value.network
        subnetwork = additional_node_network_configs.value.subnetwork
      }
    }
  }

  lifecycle {
    # Reservation blocks / queued provisioning can mutate these out of band.
    ignore_changes = [node_config[0].guest_accelerator]
  }
}
