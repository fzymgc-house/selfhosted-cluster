# ArgoCD OAuth2/OIDC Integration
# Provides single sign-on for ArgoCD GitOps platform

# Groups for ArgoCD access control
resource "authentik_group" "argocd_user" {
  name = "argocd-user"
}

resource "authentik_group" "argocd_admin" {
  name = "argocd-admin"
}

resource "authentik_group" "cluster_admin" {
  name = "cluster-admin"
}

# OAuth2 Provider for ArgoCD
resource "authentik_provider_oauth2" "argocd" {
  name      = "Provider for ArgoCD"
  client_id = "iHIWDIIDroSBtFh2XbghfT0qUVKfklpt7P2iFN6l"

  # ArgoCD uses explicit consent authorization flow
  authorization_flow    = data.authentik_flow.default_provider_authorization_explicit_consent.id
  invalidation_flow     = data.authentik_flow.default_provider_invalidation_flow.id
  access_token_validity = "minutes=5"

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://argocd.fzymgc.house/api/dex/callback"
    },
    {
      matching_mode = "strict"
      url           = "https://localhost:8085/auth/callback"
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id
  ]

  # ArgoCD uses TLS certificate for signing
  signing_key = data.authentik_certificate_key_pair.tls.id
}

# ArgoCD Application
resource "authentik_application" "argocd" {
  name              = "ArgoCD"
  slug              = "argo-cd"
  protocol_provider = authentik_provider_oauth2.argocd.id
  meta_launch_url   = "https://argocd.fzymgc.house"
}

# Store ArgoCD OIDC credentials in Vault for cluster consumption
resource "vault_kv_secret_v2" "argocd_oidc" {
  mount = "secret"
  name  = "fzymgc-house/cluster/argocd/oidc"

  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.argocd.client_id
    client_secret = authentik_provider_oauth2.argocd.client_secret
  })
}
