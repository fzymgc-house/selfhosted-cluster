// versions.tf - Required versions for Terraform and providers

terraform {
  required_version = ">= 1.14.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.0.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2025.0"
    }
  }
}
