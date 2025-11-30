# Vault OAuth2/OIDC Integration
# Provides single sign-on for HashiCorp Vault

# Data sources for Vault configuration
data "vault_kv_secret_v2" "authentik" {
  mount = "secret"
  name  = "fzymgc-house/cluster/authentik"
}

data "vault_pki_secret_backend_issuer" "fzymgc" {
  backend    = "fzymgc-house/v1/ica1/v1"
  issuer_ref = "d2c70b5d-8125-d217-f0a1-39289a096df2"
}

# Groups for Vault access control
resource "authentik_group" "vault_users" {
  name = "vault-users"
}

resource "authentik_group" "vault_admin" {
  name         = "vault-admin"
  parent       = authentik_group.vault_users.id
  is_superuser = false
}

# Vault OIDC Auth Backend Configuration
# Note: Using vault_jwt_auth_backend instead of vault_auth_backend
# as it provides full OIDC configuration support
import {
  to = vault_jwt_auth_backend.oidc
  id = "oidc"
}

locals {
  authentik_url = "https://auth.fzymgc.house/application/o/vault/"
}

resource "vault_jwt_auth_backend" "oidc" {
  path               = "oidc"
  type               = "oidc"
  oidc_client_id     = data.vault_kv_secret_v2.authentik.data["vault_oidc_client_id"]
  oidc_client_secret = data.vault_kv_secret_v2.authentik.data["vault_oidc_client_secret"]
  oidc_discovery_url = local.authentik_url
  # Note: auth.fzymgc.house uses Let's Encrypt cert, not internal CA
  # System CA store is used for certificate verification
  default_role = "reader"
}

import {
  to = vault_jwt_auth_backend_role.reader
  id = "auth/oidc/role/reader"
}

resource "vault_jwt_auth_backend_role" "reader" {
  backend         = vault_jwt_auth_backend.oidc.path
  role_name       = "reader"
  user_claim      = "sub"
  bound_audiences = [local.authentik_url, data.vault_kv_secret_v2.authentik.data["vault_oidc_client_id"]]
  token_ttl       = 3600
  token_max_ttl   = 86400
  token_policies  = ["default", "reader"]
  groups_claim    = "groups"
  # Note: groups claim is included in profile scope per Authentik docs
  oidc_scopes     = ["openid", "email", "profile"]
  allowed_redirect_uris = [
    "https://vault.fzymgc.house/ui/vault/auth/oidc/oidc/callback",
    "https://vault.fzymgc.house/oidc/callback",
    "http://localhost:8250/oidc/callback",
  ]
  verbose_oidc_logging = true
}

resource "vault_jwt_auth_backend_role" "admin" {
  backend         = vault_jwt_auth_backend.oidc.path
  role_name       = "admin"
  user_claim      = "sub"
  bound_audiences = [local.authentik_url, data.vault_kv_secret_v2.authentik.data["vault_oidc_client_id"]]
  token_ttl       = 3600
  token_max_ttl   = 86400
  token_policies  = ["default", "admin"]
  groups_claim    = "groups"
  # Note: groups claim is included in profile scope per Authentik docs
  oidc_scopes     = ["openid", "email", "profile"]
  allowed_redirect_uris = [
    "https://vault.fzymgc.house/ui/vault/auth/oidc/oidc/callback",
    "https://vault.fzymgc.house/oidc/callback",
    "http://localhost:8250/oidc/callback",
  ]
  verbose_oidc_logging = true
}

# OAuth2 Provider for Vault
resource "authentik_provider_oauth2" "vault" {
  name      = "Provider for Vault"
  client_id = "IoC5Ul9TnUprBbgPw8LoE0Ivu1X4Pv5YI0q60Bxc"

  # Vault uses explicit consent authorization flow
  authorization_flow    = data.authentik_flow.default_provider_authorization_explicit_consent.id
  invalidation_flow     = data.authentik_flow.default_provider_invalidation_flow.id
  access_token_validity = "minutes=5"

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://vault.fzymgc.house/oidc/callback"
    },
    {
      matching_mode = "strict"
      url           = "https://vault.fzymgc.house/ui/vault/auth/oidc/oidc/callback"
    },
    {
      matching_mode = "strict"
      url           = "http://localhost:8250/oidc/callback"
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.offline_access.id
  ]

  # Vault uses TLS certificate for signing
  signing_key = data.authentik_certificate_key_pair.tls.id
}

# Vault Application
resource "authentik_application" "vault" {
  name              = "Vault"
  slug              = "vault"
  protocol_provider = authentik_provider_oauth2.vault.id
  meta_launch_url   = "https://vault.fzymgc.house"
  meta_icon         = "https://vault.fzymgc.house/ui/favicon-c02e22ca67f83a0fb6f2fd265074910a.png"
}

# Store Vault OIDC credentials in Vault for cluster consumption
resource "vault_kv_secret_v2" "vault_oidc" {
  mount = "secret"
  name  = "fzymgc-house/cluster/vault/oidc"

  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.vault.client_id
    client_secret = authentik_provider_oauth2.vault.client_secret
  })
}
