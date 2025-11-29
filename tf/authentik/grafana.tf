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

  # Note: Grafana uses a different authorization flow than Mealie (which uses implicit consent).
  # This UUID was preserved during terraform import from existing Authentik configuration.
  # TODO: Identify the flow slug and create a data source reference
  authorization_flow    = "de91f0c6-7f6e-42cc-b71d-67cc48d2a82a"
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

  # Note: Grafana uses a different signing certificate than Mealie (which uses "authentik Self-signed Certificate").
  # This UUID was preserved during terraform import from existing Authentik configuration.
  # TODO: Identify the certificate name and create a data source reference
  signing_key = "55061d48-d235-40dc-834b-426736a2619c"
}

# Grafana Application
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
}
