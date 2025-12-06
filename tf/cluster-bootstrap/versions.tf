// versions.tf - Required versions for Terraform and providers

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.5"
    }
  }
}
