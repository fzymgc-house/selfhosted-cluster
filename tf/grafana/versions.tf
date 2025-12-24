// versions.tf - Required versions for Terraform and providers

terraform {
  required_version = ">= 1.12.0"
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = ">= 4.3.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 5.0"
    }
  }
}
