# SPDX-License-Identifier: MIT
# terraform: language=hcl

terraform {
  required_version = ">= 1.12.2"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.13.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
