// terraform.tf - Provider and backend configuration

terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      tags = ["main-cluster", "core-services"]
    }
  }
}

provider "kubernetes" {
  # Use kubeconfig for local dev, in-cluster auth for HCP TF agent (empty path)
  config_path    = var.kubeconfig_path != "" ? var.kubeconfig_path : null
  config_context = var.kubeconfig_context != "" ? var.kubeconfig_context : null
}

provider "helm" {
  kubernetes {
    # Use kubeconfig for local dev, in-cluster auth for HCP TF agent (empty path)
    config_path    = var.kubeconfig_path != "" ? var.kubeconfig_path : null
    config_context = var.kubeconfig_context != "" ? var.kubeconfig_context : null
  }
}
