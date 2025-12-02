# Teleport OAuth2/OIDC Integration
# Provides single sign-on for Teleport SSH and Kubernetes access

# Groups for Teleport access control
resource "authentik_group" "teleport_admins" {
  name         = "teleport-admins"
  is_superuser = false
}

resource "authentik_group" "teleport_users" {
  name         = "teleport-users"
  is_superuser = false
}

# OAuth2 Provider for Teleport
resource "authentik_provider_oauth2" "teleport" {
  name      = "Provider for Teleport"
  client_id = "teleport"

  # Teleport uses explicit consent authorization flow
  authorization_flow    = data.authentik_flow.default_provider_authorization_explicit_consent.id
  invalidation_flow     = data.authentik_flow.default_provider_invalidation_flow.id
  access_token_validity = "minutes=30"

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://teleport.fzymgc.house/v1/webapi/oidc/callback"
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id
  ]

  # Teleport uses TLS certificate for signing
  signing_key = data.authentik_certificate_key_pair.tls.id
}

# Teleport Application
resource "authentik_application" "teleport" {
  name              = "Teleport"
  slug              = "teleport"
  protocol_provider = authentik_provider_oauth2.teleport.id
  meta_launch_url   = "https://teleport.fzymgc.house"
  meta_icon         = "https://goteleport.com/static/favicons/apple-touch-icon.png"
  meta_description  = "SSH and Kubernetes access gateway"
}

# Store OAuth2 credentials in Vault
resource "vault_kv_secret_v2" "teleport_oidc" {
  mount = "secret"
  name  = "fzymgc-house/cluster/teleport/oidc"

  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.teleport.client_id
    client_secret = authentik_provider_oauth2.teleport.client_secret
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by  = "terraform"
      application = "teleport"
    }
  }
}
