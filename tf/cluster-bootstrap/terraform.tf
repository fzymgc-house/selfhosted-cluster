terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      tags = ["main-cluster", "bootstrap"]
    }
  }
}

provider "helm" {
  kubernetes = {
    config_path = pathexpand("~/.kube/configs/fzymgc-house-admin.yml")
  }
}

provider "kubernetes" {
  config_path = pathexpand("~/.kube/configs/fzymgc-house-admin.yml")
}

provider "vault" {
  address = "https://vault.fzymgc.house"
  # Auth via VAULT_TOKEN environment variable
}
