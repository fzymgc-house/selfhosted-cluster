# NAS LDAP Integration
# Provides LDAP authentication for Network Attached Storage (Samba/NFS)

# LDAP Provider for NAS
resource "authentik_provider_ldap" "nas" {
  name    = "Provider for NAS"
  base_dn = "DC=ldap,DC=fzymgc,DC=house"

  # Bind mode determines how NAS authenticates LDAP users
  bind_mode   = "cached"
  search_mode = "cached"

  # Unix UID/GID ranges for LDAP user attributes
  uid_start_number = 2000
  gid_start_number = 4000

  # MFA support enabled for enhanced security
  mfa_support = true

  # TLS configuration
  tls_server_name = "auth.fzymgc.house"

  # NAS uses default authentication flow for LDAP bind
  bind_flow = data.authentik_flow.default_authentication_flow.id

  # Unbind flow matches default_invalidation_flow
  unbind_flow = data.authentik_flow.default_invalidation_flow.id

  # NAS uses TLS certificate (same as Grafana)
  certificate = data.authentik_certificate_key_pair.tls.id
}

# NAS Application
#  Note: policy_engine_mode is set to "all" (requires all policies to pass).
# This is different from the default "any" used by some other applications.
resource "authentik_application" "nas" {
  name               = "NAS"
  slug               = "nas"
  protocol_provider  = authentik_provider_ldap.nas.id
  meta_launch_url    = "https://nas.fzymgc.house"
  policy_engine_mode = "all"
}

# Note: Unlike OAuth2 providers, LDAP providers in cached mode don't have
# bind credentials to store. NAS connects to Authentik's LDAP outpost which
# handles authentication internally. Users authenticate directly to Authentik,
# and their credentials are cached for LDAP queries.
