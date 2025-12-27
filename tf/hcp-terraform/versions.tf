// versions.tf - Required versions for Terraform and providers

terraform {
  required_version = "~> 1.14.0"

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.72"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.6"
    }
  }
}
