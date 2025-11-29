# Mealie OAuth2 Provider and Application
#
# Integrates Mealie recipe manager with Authentik for SSO
# References:
# - https://integrations.goauthentik.io/documentation/mealie/
# - https://docs.mealie.io/documentation/getting-started/authentication/oidc-v2/

# Groups for Mealie access control
resource "authentik_group" "mealie_users" {
  name = "mealie-users"
}

resource "authentik_group" "mealie_admins" {
  name         = "mealie-admins"
  parent       = authentik_group.mealie_users.id
  is_superuser = false
}

# OAuth2 Provider for Mealie
resource "authentik_provider_oauth2" "mealie" {
  name        = "Mealie"
  client_type = "confidential"
  client_id   = "mealie"

  # Mealie uses explicit consent authorization flow (standardized across all apps)
  authorization_flow = data.authentik_flow.default_provider_authorization_explicit_consent.id
  invalidation_flow  = data.authentik_flow.default_provider_invalidation_flow.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://mealie.fzymgc.house/login"
    },
    {
      matching_mode = "strict"
      url           = "https://mealie.fzymgc.house/login?direct=1"
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id
  ]

  # Mealie uses TLS certificate for signing (standardized across all apps)
  signing_key = data.authentik_certificate_key_pair.tls.id
}

# Application for Mealie
resource "authentik_application" "mealie" {
  name              = "Mealie"
  slug              = "mealie"
  protocol_provider = authentik_provider_oauth2.mealie.id
  meta_launch_url   = "https://mealie.fzymgc.house"
  meta_description  = "Recipe manager and meal planner"
  meta_publisher    = "mealie-recipes"

  lifecycle {
    ignore_changes = [
      meta_icon
    ]
  }
}

# Read existing Mealie secrets from Vault (OpenAI API key, base_url, allow_signup)
data "vault_kv_secret_v2" "mealie_existing" {
  mount = "secret"
  name  = "fzymgc-house/cluster/mealie"
}

# Store OAuth2 credentials in Vault (merge with existing secrets)
resource "vault_kv_secret_v2" "mealie" {
  mount = "secret"
  name  = "fzymgc-house/cluster/mealie"

  data_json = jsonencode(merge(
    data.vault_kv_secret_v2.mealie_existing.data,
    {
      oidc_client_id      = authentik_provider_oauth2.mealie.client_id
      oidc_client_secret  = authentik_provider_oauth2.mealie.client_secret
      oidc_auth_enabled   = "true"
      oidc_signup_enabled = "true"
      oidc_user_group     = authentik_group.mealie_users.name
      oidc_admin_group    = authentik_group.mealie_admins.name
    }
  ))

  custom_metadata {
    max_versions = 5
    data = {
      managed_by  = "terraform"
      application = "mealie"
    }
  }
}
