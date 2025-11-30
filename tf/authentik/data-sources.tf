# Data sources shared across multiple applications
# These reference Authentik's default flows and resources

# Default authorization flow (explicit consent) - used by all OAuth2 apps
data "authentik_flow" "default_provider_authorization_explicit_consent" {
  slug = "default-provider-authorization-explicit-consent"
}

# Default authentication flow - used by NAS LDAP bind flow
data "authentik_flow" "default_authentication_flow" {
  slug = "default-authentication-flow"
}

# Default invalidation flow
data "authentik_flow" "default_invalidation_flow" {
  slug = "default-invalidation-flow"
}

# Default provider invalidation flow
data "authentik_flow" "default_provider_invalidation_flow" {
  slug = "default-provider-invalidation-flow"
}

# TLS certificate - used by all apps
data "authentik_certificate_key_pair" "tls" {
  name = "tls"
}

# Standard OAuth2 scope mappings
data "authentik_property_mapping_provider_scope" "email" {
  managed = "goauthentik.io/providers/oauth2/scope-email"
}

data "authentik_property_mapping_provider_scope" "openid" {
  managed = "goauthentik.io/providers/oauth2/scope-openid"
}

data "authentik_property_mapping_provider_scope" "profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

data "authentik_property_mapping_provider_scope" "offline_access" {
  managed = "goauthentik.io/providers/oauth2/scope-offline_access"
}

# Groups scope mapping - required for applications that need group membership
data "authentik_property_mapping_provider_scope" "groups" {
  managed = "goauthentik.io/providers/oauth2/scope-groups"
}
