// terraform.tf - Provider and backend configuration

terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      tags = ["main-cluster", "hcp-terraform"]
    }
  }
}

provider "tfe" {
  # Uses TFE_TOKEN environment variable
}

provider "vault" {
  address = var.vault_addr

  # HCP Terraform workload identity authentication
  # When running in HCP TF agent, authenticates via JWT token file
  # For local development, use VAULT_TOKEN environment variable
  dynamic "auth_login_jwt" {
    for_each = var.tfc_workload_identity_token_path != "" ? [1] : []

    content {
      mount = "jwt-hcp-terraform"
      role  = "tfc-hcp-terraform"
      jwt   = file(var.tfc_workload_identity_token_path)
    }
  }

  skip_child_token = true
}
