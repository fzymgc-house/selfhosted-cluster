// versions.tf - Required versions for Terraform and providers

terraform {
  required_version = "~> 1.14.0"
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.20"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.6"
    }
  }
}
