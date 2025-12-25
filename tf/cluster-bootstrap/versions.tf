// versions.tf - Required versions for Terraform and providers

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.5"
    }
  }
}
