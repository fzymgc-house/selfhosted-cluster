// versions.tf - Required versions for Terraform and providers

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.0.1"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.6.0"
    }
  }
}
