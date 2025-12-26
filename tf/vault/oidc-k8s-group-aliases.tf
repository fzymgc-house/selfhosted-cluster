# tf/vault/oidc-k8s-group-aliases.tf
# Map Authentik group claims to Vault identity groups.
#
# When users authenticate via OIDC with Authentik, their group memberships
# are included in the token. These aliases connect those group names to
# Vault's external identity groups (defined in groups-and-roles.tf),
# which have policies attached (defined in policy-k8s-access.tf).
#
# Flow: User logs in via OIDC -> Authentik includes groups in token ->
#       Vault matches group name to alias -> Alias points to identity group ->
#       User receives policies from that group

data "vault_auth_backend" "oidc" {
  path = "oidc"
}

resource "vault_identity_group_alias" "k8s_admins" {
  name           = "k8s-admins"
  mount_accessor = data.vault_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.k8s_admins.id
}

resource "vault_identity_group_alias" "k8s_developers" {
  name           = "k8s-developers"
  mount_accessor = data.vault_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.k8s_developers.id
}

resource "vault_identity_group_alias" "k8s_viewers" {
  name           = "k8s-viewers"
  mount_accessor = data.vault_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.k8s_viewers.id
}
