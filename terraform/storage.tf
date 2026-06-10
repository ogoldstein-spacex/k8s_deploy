###############################################################################
# Shared POSIX storage (Filestore / NFS) for /home, datasets and checkpoints.
# Mounted by both Slurm nodes and Jupyter notebooks so prototyping and full
# training jobs share the same filesystem.
#
# For very high-throughput training (multi-hundred GB/s), swap this for
# Managed Lustre or Parallelstore; the Slurm/Jupyter mounts stay the same.
###############################################################################

resource "google_filestore_instance" "shared" {
  count    = var.filestore_enabled ? 1 : 0
  name     = "${var.name_prefix}-shared"
  location = var.zone
  tier     = var.filestore_tier

  file_shares {
    name        = "shared"
    capacity_gb = var.filestore_capacity_gb
  }

  networks {
    network = google_compute_network.host.name
    modes   = ["MODE_IPV4"]
  }

  depends_on = [google_project_service.enabled]
}
