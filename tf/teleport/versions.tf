// versions.tf - Required versions for Terraform and providers

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = "~> 17.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
  }
}
