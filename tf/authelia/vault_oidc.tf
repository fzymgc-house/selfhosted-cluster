# import {
#   id = "oidc"
#   to = vault_jwt_auth_backend.main
# }

data "vault_pki_secret_backend_issuer" "fzymgc" {
  backend = "fzymgc-house/v1/ica1/v1"
  issuer_ref = "95f81d15-1d5d-c8b0-813f-7caacb3915c8"
}

resource "vault_jwt_auth_backend" "main" {
  path = "oidc"
  type = "oidc"
  oidc_discovery_url = "https://auth.fzymgc.house"
  bound_issuer = "https://auth.fzymgc.house/"
  oidc_client_id = "3GN4JFyF~N3bRddT2krDfy.eAfygs8eFNdaCMJmxmnl0gHC42iIdIvaO5i_qZznnB~Z0ZIw9"
  oidc_client_secret = var.vault_oidc_client_secret
  oidc_discovery_ca_pem = "${join("\n", data.vault_pki_secret_backend_issuer.fzymgc.ca_chain)}"
}

resource "vault_jwt_auth_backend_role" "default" {
  backend = vault_jwt_auth_backend.main.path
  role_name = "default"
  role_type = "oidc"
  token_policies = ["default"]
  user_claim = "sub"
  bound_audiences = [
    "https://auth.fzymgc.house/"
  ]
  allowed_redirect_uris = [
    "https://vault.fzymgc.house/ui/vault/auth/oidc/oidc/callback",
    "https://vault.fzymgc.house/oidc/oidc/callback",
    "https://vault.fzymgc.house/oidc/callback"
  ]
}


