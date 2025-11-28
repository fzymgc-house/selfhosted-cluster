# Data sources shared across multiple applications
# These reference Authentik's default flows and resources

# Default authorization flow (implicit consent)
data "authentik_flow" "default_authorization_flow" {
  slug = "default-provider-authorization-implicit-consent"
}

# Default invalidation flow
data "authentik_flow" "default_invalidation_flow" {
  slug = "default-invalidation-flow"
}

# Default provider invalidation flow
data "authentik_flow" "default_provider_invalidation_flow" {
  slug = "default-provider-invalidation-flow"
}

# Default self-signed certificate for signing
data "authentik_certificate_key_pair" "generated" {
  name = "authentik Self-signed Certificate"
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
  # Note: The profile scope includes the groups claim in Authentik
  # Groups are provided via: "groups": [group.name for group in request.user.ak_groups.all()]
}

data "authentik_property_mapping_provider_scope" "offline_access" {
  managed = "goauthentik.io/providers/oauth2/scope-offline_access"
}
