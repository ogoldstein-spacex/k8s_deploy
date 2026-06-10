###############################################################################
# Core project / location
###############################################################################

variable "project_id" {
  type        = string
  description = "GCP project ID to deploy into."
}

variable "region" {
  type        = string
  description = "Compute region for the regional GKE cluster (control plane + subnets)."
  default     = "us-central1"
}

variable "zone" {
  type        = string
  description = <<-EOT
    Single zone used for the GPU node pool. GPUDirect-RDMA node pools must be
    single-zone, and the zone must match your GPU capacity reservation. The
    RDMA VPC RoCE network profile is also zone-scoped (`<zone>-vpc-roce`).
  EOT
  default     = "us-central1-b"
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to all created resources (cluster, networks, pools)."
  default     = "ml"
}

###############################################################################
# GKE cluster
###############################################################################

variable "release_channel" {
  type        = string
  description = "GKE release channel. RAPID is recommended to access the newest GPU/RDMA features."
  default     = "RAPID"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of RAPID, REGULAR, STABLE."
  }
}

variable "min_master_version" {
  type        = string
  description = <<-EOT
    Optional minimum control plane version. GPUDirect-RDMA on A3 Ultra requires
    >= 1.31.5-gke.1169000 and A4/B200 requires >= 1.32. Leave empty to let the
    release channel pick the default.
  EOT
  default     = ""
}

###############################################################################
# Networking (host + GPU RDMA fabric)
###############################################################################

variable "cluster_subnet_cidr" {
  type        = string
  description = "Primary CIDR for the GKE node subnet in the host VPC."
  default     = "10.0.0.0/20"
}

variable "pods_cidr" {
  type        = string
  description = "Secondary range for GKE Pods (alias IPs)."
  default     = "10.4.0.0/14"
}

variable "services_cidr" {
  type        = string
  description = "Secondary range for GKE Services."
  default     = "10.8.0.0/20"
}

variable "master_ipv4_cidr" {
  type        = string
  description = "CIDR for the private control plane endpoint."
  default     = "172.16.0.0/28"
}

variable "gvnic_network_prefix" {
  type        = string
  description = "Name prefix for the secondary Titanium (gVNIC) VPC + subnet."
  default     = "a3ultra-gvnic"
}

variable "rdma_network_prefix" {
  type        = string
  description = "Name prefix for the RDMA (RoCE) VPC + its 8 GPU-NIC subnets."
  default     = "a3ultra-rdma"
}

variable "rdma_subnet_count" {
  type        = number
  description = "Number of RDMA GPU-NIC subnets. A3 Ultra / A4 have 8 CX-7 NICs."
  default     = 8
}

###############################################################################
# GPU node pool (the expensive, training pool)
###############################################################################

variable "gpu_machine_type" {
  type        = string
  description = "A3 Ultra (a3-ultragpu-8g / H200) or A4 (a4-highgpu-8g / B200)."
  default     = "a3-ultragpu-8g"
}

variable "gpu_accelerator_type" {
  type        = string
  description = "GPU accelerator. H200: nvidia-h200-141gb. B200: nvidia-b200."
  default     = "nvidia-h200-141gb"
}

variable "gpu_per_node" {
  type        = number
  description = "GPUs per node (8 for a3-ultragpu-8g and a4-highgpu-8g)."
  default     = 8
}

variable "gpu_driver_version" {
  type        = string
  description = "GKE-managed driver version. H200/B200 require LATEST (R550+)."
  default     = "LATEST"
}

variable "gpu_min_nodes" {
  type        = number
  description = "Minimum nodes in the GPU pool. Keep at 0 to avoid idle GPU spend."
  default     = 0
}

variable "gpu_max_nodes" {
  type        = number
  description = "Maximum nodes the GPU pool can autoscale to."
  default     = 4
}

###############################################################################
# GPU capacity model: a reservation (recommended) OR DWS flex-start.
###############################################################################

variable "gpu_capacity_mode" {
  type        = string
  description = "How to obtain GPU capacity: 'reservation', 'flex_start', or 'spot'."
  default     = "reservation"

  validation {
    condition     = contains(["reservation", "flex_start", "spot"], var.gpu_capacity_mode)
    error_message = "gpu_capacity_mode must be one of reservation, flex_start, spot."
  }
}

variable "reservation_name" {
  type        = string
  description = "Name of the specific GPU reservation (used when gpu_capacity_mode = reservation)."
  default     = ""
}

###############################################################################
# Dev (JupyterLab) pool: cheap L4 GPUs for quick tests, scales to zero.
###############################################################################

variable "dev_machine_type" {
  type        = string
  description = "Machine type for the cheap dev/notebook GPU pool."
  default     = "g2-standard-12"
}

variable "dev_accelerator_type" {
  type        = string
  description = "Accelerator for the dev pool (L4 is cheap and great for quick tests)."
  default     = "nvidia-l4"
}

variable "dev_gpu_per_node" {
  type    = number
  default = 1
}

variable "dev_max_nodes" {
  type    = number
  default = 2
}

###############################################################################
# Shared storage
###############################################################################

variable "filestore_enabled" {
  type        = bool
  description = "Provision a Filestore (NFS) instance for shared /home + checkpoints."
  default     = true
}

variable "filestore_tier" {
  type        = string
  description = "Filestore service tier (BASIC_SSD, ZONAL, ENTERPRISE)."
  default     = "ZONAL"
}

variable "filestore_capacity_gb" {
  type        = number
  description = "Filestore capacity in GiB (ZONAL/SSD minimums apply)."
  default     = 1024
}
