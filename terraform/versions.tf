terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.8.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6.8.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }

  # Remote state is strongly recommended for a shared platform. Uncomment and
  # point this at a GCS bucket you control, then run `terraform init`.
  #
  # backend "gcs" {
  #   bucket = "my-tfstate-bucket"
  #   prefix = "k8s-deploy/gke-slinky"
  # }
}
