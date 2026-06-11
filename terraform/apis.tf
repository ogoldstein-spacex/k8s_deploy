locals {
  required_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "file.googleapis.com", # Filestore
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com", # required by google_project_iam_member
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]
}

resource "google_project_service" "enabled" {
  for_each = toset(local.required_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
