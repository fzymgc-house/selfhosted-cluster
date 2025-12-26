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
