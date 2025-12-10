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

# Data source for fzymgc.house zone
data "cloudflare_zone" "fzymgc_house" {
  filter = {
    name = "fzymgc.house"
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
