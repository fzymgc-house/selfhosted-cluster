# Grafana OAuth2/OIDC Integration
# Provides single sign-on for Grafana metrics and monitoring platform

# Groups for Grafana access control
resource "authentik_group" "grafana_editor" {
  name = "grafana-editor"
}

resource "authentik_group" "grafana_admin" {
  name         = "grafana-admin"
  parent       = authentik_group.grafana_editor.id
  is_superuser = false
}

# OAuth2 Provider for Grafana
resource "authentik_provider_oauth2" "grafana" {
  name      = "Provider for Grafana"
  client_id = "XVTJeC00KCGqBu3NduFHwyZ5LzQP7khbCymqQIhP"

  # Grafana uses explicit consent authorization flow (different from Mealie's implicit consent)
  authorization_flow    = data.authentik_flow.default_provider_authorization_explicit_consent.id
  invalidation_flow     = data.authentik_flow.default_provider_invalidation_flow.id
  access_token_validity = "minutes=5"

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://grafana.fzymgc.house/login/generic_oauth"
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id
  ]

  # Grafana uses TLS certificate for signing (different from Mealie's self-signed certificate)
  signing_key = data.authentik_certificate_key_pair.tls.id
}

# Grafana Application
# Note: policy_engine_mode defaults to "any" (allows access if any policy passes).
# This was changed from "all" during import to match Authentik defaults.
resource "authentik_application" "grafana" {
  name              = "Grafana"
  slug              = "grafana"
  protocol_provider = authentik_provider_oauth2.grafana.id
  meta_launch_url   = "https://grafana.fzymgc.house"
  meta_description  = "Metrics and monitoring dashboards"
}

# Read existing Grafana secrets from Vault
data "vault_kv_secret_v2" "grafana_existing" {
  mount = "secret"
  name  = "fzymgc-house/cluster/grafana"
}

# Store OAuth2 credentials in Vault (merge with existing secrets)
resource "vault_kv_secret_v2" "grafana" {
  mount = "secret"
  name  = "fzymgc-house/cluster/grafana"

  data_json = jsonencode(merge(
    data.vault_kv_secret_v2.grafana_existing.data,
    {
      oidc_client_id     = authentik_provider_oauth2.grafana.client_id
      oidc_client_secret = authentik_provider_oauth2.grafana.client_secret
    }
  ))

  custom_metadata {
    max_versions = 5
    data = {
      managed_by  = "terraform"
      application = "grafana"
    }
  }
}
