import {
  to = vault_identity_group.reader
  id = "e1165c10-0592-4885-836b-865ac465c593"
}

resource "vault_identity_group" "reader" {
  name     = "reader"
  type     = "external"
  policies = ["reader"]
}

import {
  to = vault_identity_group.admin
  id = "e276baa3-366a-1e4a-7afa-17503360994c"
}

resource "vault_identity_group" "admin" {
  name     = "admin"
  type     = "external"
  policies = ["admin"]
}

resource "vault_identity_group_member_entity_ids" "admin" {
  group_id          = vault_identity_group.admin.id
  member_entity_ids = [vault_identity_entity.sean.id]
}

# =============================================================================
# Kubernetes Access Groups
# =============================================================================
# External groups that map to Authentik groups via OIDC.
# When users authenticate via OIDC with these Authentik groups,
# they receive the corresponding Vault policies.

resource "vault_identity_group" "k8s_admins" {
  name     = "k8s-admins"
  type     = "external"
  policies = [vault_policy.k8s_admin_cert.name]
}

resource "vault_identity_group" "k8s_developers" {
  name     = "k8s-developers"
  type     = "external"
  policies = [vault_policy.k8s_developer_cert.name]
}

resource "vault_identity_group" "k8s_viewers" {
  name     = "k8s-viewers"
  type     = "external"
  policies = [vault_policy.k8s_viewer_cert.name]
}
