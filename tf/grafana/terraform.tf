# terraform.tf - Provider and backend configuration

terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      tags = ["main-cluster", "grafana"]
    }
  }
}

provider "vault" {
  address          = var.tfc_vault_dynamic_credentials != null ? var.tfc_vault_dynamic_credentials.default.address : var.vault_addr
  skip_child_token = var.tfc_vault_dynamic_credentials != null

  # Dynamic credentials: HCP TF handles JWT auth and writes Vault token to file
  dynamic "auth_login_token_file" {
    for_each = var.tfc_vault_dynamic_credentials != null ? [1] : []
    content {
      filename = var.tfc_vault_dynamic_credentials.default.token_filename
    }
  }
}
