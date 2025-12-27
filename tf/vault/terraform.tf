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
  # Use dynamic credentials address when available, otherwise use variable
  address          = var.tfc_vault_dynamic_credentials != null ? var.tfc_vault_dynamic_credentials.default.address : var.vault_addr
  skip_child_token = var.tfc_vault_dynamic_credentials != null

  # Dynamic credentials: HCP TF handles JWT auth and writes Vault token to file
  # For local dev: uses VAULT_TOKEN environment variable (no auth block needed)
  dynamic "auth_login_token_file" {
    for_each = var.tfc_vault_dynamic_credentials != null ? [1] : []
    content {
      filename = var.tfc_vault_dynamic_credentials.default.token_filename
    }
  }
}

provider "kubernetes" {
  # Use kubeconfig for local dev, in-cluster auth for HCP TF agent (empty path)
  config_path    = var.kubeconfig_path != "" ? var.kubeconfig_path : null
  config_context = var.kubeconfig_context != "" ? var.kubeconfig_context : null
}
