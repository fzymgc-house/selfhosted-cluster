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
  # Uses VAULT_TOKEN environment variable
  # This workspace runs in local mode (not agent) due to circular dependency -
  # it manages the agent pool configuration itself
  skip_child_token = true
}
