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

  # Note: NAS uses a different bind flow than other applications.
  # This UUID was preserved during terraform import from existing Authentik configuration.
  # TODO: Identify the flow slug and create a data source reference
  bind_flow = "b8c1dc50-547b-454d-8015-04202a9bdb17"

  # Unbind flow matches default_invalidation_flow
  unbind_flow = data.authentik_flow.default_invalidation_flow.id

  # Note: NAS uses the "tls" certificate (same as Grafana signing key).
  # This UUID was preserved during terraform import from existing Authentik configuration.
  # TODO: Identify the certificate name and create a data source reference
  certificate = "55061d48-d235-40dc-834b-426736a2619c"
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
