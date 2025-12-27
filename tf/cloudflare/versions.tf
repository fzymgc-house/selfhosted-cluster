# SPDX-License-Identifier: MIT
# terraform: language=hcl

terraform {
  required_version = "~> 1.14.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.14"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
