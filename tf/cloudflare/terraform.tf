# SPDX-License-Identifier: MIT
# terraform: language=hcl

provider "cloudflare" {
  api_token = data.vault_kv_secret_v2.cloudflare_token.data["token"]
}

provider "vault" {
  # Configuration inherited from environment:
  # - VAULT_ADDR
  # - VAULT_TOKEN (from vault login)
}

# Data source for Cloudflare API token
data "vault_kv_secret_v2" "cloudflare_token" {
  mount = "secret"
  name  = "fzymgc-house/infrastructure/cloudflare/api-token"
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
