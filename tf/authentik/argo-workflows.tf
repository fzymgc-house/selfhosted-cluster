# Argo Workflows OAuth2/OIDC Integration
# Provides single sign-on for Argo Workflows platform

# OAuth2 Provider for Argo Workflows
resource "authentik_provider_oauth2" "argo_workflows" {
  name      = "Provider for Argo Workflow"
  client_id = "3DgaUYpDvHyMuuXGiMVwZXOJzCmTxBeQydZYYF8Z"

  # Argo Workflows uses explicit consent authorization flow
  authorization_flow    = data.authentik_flow.default_provider_authorization_explicit_consent.id
  invalidation_flow     = data.authentik_flow.default_provider_invalidation_flow.id
  access_token_validity = "minutes=5"

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://argo-workflows.fzymgc.house/oauth2/callback"
    },
    {
      matching_mode = "strict"
      url           = "https://argoworkflows.fzymgc.house/oauth2/callback"
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id
  ]

  # Argo Workflows uses TLS certificate for signing
  signing_key = data.authentik_certificate_key_pair.tls.id
}

# Argo Workflows Application
resource "authentik_application" "argo_workflows" {
  name              = "Argo Workflow"
  slug              = "argo-workflow"
  protocol_provider = authentik_provider_oauth2.argo_workflows.id
  meta_launch_url   = "https://argo-workflows.fzymgc.house"
}

# Store Argo Workflows OIDC credentials in Vault for cluster consumption
resource "vault_kv_secret_v2" "argo_workflows_oidc" {
  mount = "secret"
  name  = "fzymgc-house/cluster/argo-workflows/oidc"

  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.argo_workflows.client_id
    client_secret = authentik_provider_oauth2.argo_workflows.client_secret
  })
}
