provider "vault" {
  address = "https://vault.fzymgc.house"
}

provider "authentik" {
  url   = "https://auth.fzymgc.house"
  token = data.vault_kv_secret_v2.authentik.data["terraform_token"]
}

terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      tags = ["main-cluster", "authentik"]
    }
  }
}
