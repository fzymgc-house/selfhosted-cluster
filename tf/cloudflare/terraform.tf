# SPDX-License-Identifier: MIT
# terraform: language=hcl

provider "cloudflare" {
  api_token = data.vault_kv_secret_v2.cloudflare_bootstrap_token.data["token"]
}

provider "vault" {
  address = var.vault_addr

  # Use OIDC when running in HCP TF, fallback to token for local dev
  dynamic "auth_login_jwt" {
    for_each = var.tfc_workload_identity_token_path != "" ? [1] : []
    content {
      mount = "jwt-hcp-terraform"
      role  = "tfc-cloudflare"
      jwt   = file(var.tfc_workload_identity_token_path)
    }
  }
}

# Data source for Cloudflare bootstrap API token
# This token has: API Tokens:Edit + all operational permissions
# It's used by Terraform to authenticate and create the workload token
# See api-tokens.tf for the two-token pattern documentation
data "vault_kv_secret_v2" "cloudflare_bootstrap_token" {
  mount = "secret"
  name  = "fzymgc-house/infrastructure/cloudflare/bootstrap-token"
}

# Data source for fzymgc.house zone (internal services)
data "cloudflare_zone" "fzymgc_house" {
  filter = {
    name = "fzymgc.house"
  }
}

# Data source for fzymgc.net zone (external/webhook services)
# Using separate domain avoids split-horizon DNS issues with internal fzymgc.house
data "cloudflare_zone" "fzymgc_net" {
  filter = {
    name = "fzymgc.net"
  }
}

terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      tags = ["main-cluster", "cloudflared"]
    }
  }
}
