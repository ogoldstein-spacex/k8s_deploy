###############################################################################
# Host VPC: GKE nodes, pods, services, control-plane egress via Cloud NAT.
###############################################################################

resource "google_compute_network" "host" {
  name                    = "${var.name_prefix}-host-net"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.enabled]
}

resource "google_compute_subnetwork" "cluster" {
  name          = "${var.name_prefix}-cluster-subnet"
  ip_cidr_range = var.cluster_subnet_cidr
  region        = var.region
  network       = google_compute_network.host.id

  # Required for GPUDirect/gVNIC line-rate networking.
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

# Private nodes need a NAT for image pulls / package installs.
resource "google_compute_router" "router" {
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = google_compute_network.host.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.name_prefix}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_firewall" "host_internal" {
  name      = "${var.name_prefix}-host-internal"
  network   = google_compute_network.host.id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.cluster_subnet_cidr, var.pods_cidr]
}

###############################################################################
# Secondary Titanium NIC VPC (gVNIC) -> exposed in-cluster as Network "gvnic-1".
###############################################################################

resource "google_compute_network" "gvnic" {
  name                    = "${var.gvnic_network_prefix}-net"
  auto_create_subnetworks = false
  mtu                     = 8896
  depends_on              = [google_project_service.enabled]
}

resource "google_compute_subnetwork" "gvnic" {
  name          = "${var.gvnic_network_prefix}-sub"
  ip_cidr_range = "192.168.0.0/24"
  region        = var.region
  network       = google_compute_network.gvnic.id
}

resource "google_compute_firewall" "gvnic_internal" {
  name      = "${var.gvnic_network_prefix}-internal"
  network   = google_compute_network.gvnic.id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["192.168.0.0/16"]
}

###############################################################################
# RDMA (RoCE) VPC + one subnet per CX-7 NIC -> Networks "rdma-0".."rdma-7".
# The RoCE network profile is zone-scoped and requires the google-beta provider.
###############################################################################

resource "google_compute_network" "rdma" {
  provider                = google-beta
  name                    = "${var.rdma_network_prefix}-net"
  auto_create_subnetworks = false
  mtu                     = 8896
  network_profile         = "projects/${var.project_id}/global/networkProfiles/${var.zone}-vpc-roce"
  depends_on              = [google_project_service.enabled]
}

resource "google_compute_subnetwork" "rdma" {
  provider      = google-beta
  count         = var.rdma_subnet_count
  name          = "${var.rdma_network_prefix}-sub-${count.index}"
  ip_cidr_range = "192.168.${count.index + 1}.0/24"
  region        = var.region
  network       = google_compute_network.rdma.id
}
