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
import {
  to = vault_auth_backend.oidc
  id = "oidc"
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
  path                  = "oidc"
  type                  = "oidc"
  oidc_client_id        = data.vault_kv_secret_v2.authentik.data["vault_oidc_client_id"]
  oidc_client_secret    = data.vault_kv_secret_v2.authentik.data["vault_oidc_client_secret"]
  oidc_discovery_url    = local.authentik_url
  oidc_discovery_ca_pem = join("\n", data.vault_pki_secret_backend_issuer.fzymgc.ca_chain)
  jwks_ca_pem           = join("\n", data.vault_pki_secret_backend_issuer.fzymgc.ca_chain)
  default_role          = "reader"
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
  oidc_scopes     = ["openid", "email", "profile", "groups"]
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
  oidc_scopes     = ["openid", "email", "profile", "groups"]
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

  authorization_flow    = "de91f0c6-7f6e-42cc-b71d-67cc48d2a82a"
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

  signing_key = "55061d48-d235-40dc-834b-426736a2619c"
}
