provider "vault" {
  address = var.vault_addr

  # Use OIDC when running in HCP TF, fallback to token for local dev
  dynamic "auth_login_jwt" {
    for_each = var.tfc_workload_identity_token_path != "" ? [1] : []
    content {
      mount = "jwt-hcp-terraform"
      role  = "tfc-authentik"
      jwt   = file(var.tfc_workload_identity_token_path)
    }
  }
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
