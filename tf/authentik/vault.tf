import {
  to = vault_auth_backend.oidc
  id = "oidc"
}

data "vault_pki_secret_backend_issuer" "fzymgc" {
  backend = "fzymgc-house/v1/ica1/v1"
  issuer_ref = "d2c70b5d-8125-d217-f0a1-39289a096df2"
}

resource "vault_auth_backend" "oidc" {
  type = "oidc"
  path = "oidc"
}

import {
  to = vault_jwt_auth_backend.oidc
  id = "oidc"
}

locals {
  authentik_url = "https://auth.fzymgc.house/application/o/vault/"
}

resource "vault_jwt_auth_backend" "oidc" {
  path = "oidc"
  type = "oidc"
  oidc_client_id = var.authentik_client_id
  oidc_client_secret = var.authentik_client_secret
  oidc_discovery_url = local.authentik_url
  oidc_discovery_ca_pem = join("\n", data.vault_pki_secret_backend_issuer.fzymgc.ca_chain)
  jwks_ca_pem = join("\n", data.vault_pki_secret_backend_issuer.fzymgc.ca_chain)
  default_role = "reader"
}

resource "vault_jwt_auth_backend_role" "reader" {
  backend = vault_jwt_auth_backend.oidc.path
  role_name = "reader"
  user_claim = "sub"
  bound_audiences = [local.authentik_url, var.authentik_client_id]
  token_ttl = 3600
  token_max_ttl = 86400
  token_policies = ["default","reader"]
  groups_claim = "groups"
  oidc_scopes = ["openid", "email", "profile", "groups"]
  allowed_redirect_uris = [
    "https://vault.fzymgc.house/ui/vault/auth/oidc/oidc/callback",
    "https://vault.fzymgc.house/oidc/callback",
    "https://localhost:8250/oidc/callback",
  ]
  verbose_oidc_logging = true
}

data "vault_identity_group" "reader" {
  group_name = "reader"
}

data "vault_identity_group" "admin" {
  group_name = "admin"
}

import {
  to = vault_identity_group_alias.reader
  id = "reader"
}

import {
  to = vault_identity_group_alias.admin
  id = "admin"
}

resource "vault_identity_group_alias" "reader" {
  mount_accessor = vault_jwt_auth_backend.oidc.accessor
  canonical_id = data.vault_identity_group.reader.id
  name = "reader"
}

resource "vault_identity_group_alias" "admin" {
  mount_accessor = vault_jwt_auth_backend.oidc.accessor
  canonical_id = data.vault_identity_group.admin.id
  name = "admin"
}