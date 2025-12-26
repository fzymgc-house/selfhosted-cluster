// terraform.tf - Provider and backend configuration

terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      tags = ["main-cluster", "vault"]
    }
  }
}

provider "vault" {
  address = var.vault_addr

  # Use OIDC when running in HCP TF, fallback to token for local dev
  dynamic "auth_login_jwt" {
    for_each = var.tfc_workload_identity_token_path != "" ? [1] : []
    content {
      mount = "jwt-hcp-terraform"
      role  = "tfc-vault"
      jwt   = file(var.tfc_workload_identity_token_path)
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/configs/fzymgc-house-admin.yml"
  config_context = "fzymgc-house"
}
