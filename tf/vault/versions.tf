// versions.tf - Required versions for Terraform and providers

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "2.2.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.3.0"
    }
  }
}
