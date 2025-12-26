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
  config_path    = "~/.kube/configs/fzymgc-house-admin.yml"
  config_context = "fzymgc-house"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/configs/fzymgc-house-admin.yml"
    config_context = "fzymgc-house"
  }
}
