// versions.tf - Required versions for Terraform and providers

terraform {
  required_version = ">= 1.12.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "2.2.1"
    }
    helm = {
      source = "hashicorp/helm"
      version = "3.1.1"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2024.8"
    }
  }
}
