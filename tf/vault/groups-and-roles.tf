import {
  to = vault_identity_group.reader
  id = "e1165c10-0592-4885-836b-865ac465c593"
}

resource "vault_identity_group" "reader" {
  name = "reader"
  type = "external"
  policies = ["reader"]
}

import {
  to = vault_identity_group.admin
  id = "e276baa3-366a-1e4a-7afa-17503360994c"
}

resource "vault_identity_group" "admin" {
  name = "admin"
  type = "external"
  policies = ["admin"]
}

import {
  to = vault_identity_group.tofu-runner
  id = "df234798-81e1-df81-468f-b251cc5a24dd"
}

resource "vault_identity_group" "tofu-runner" {
  name = "tofu-runner"
  type = "internal"
  policies = [
    vault_policy.policy-admin.name,
    vault_policy.token-create.name,
    vault_policy.kubernetes-config-admin.name,
    vault_policy.ldap-config-admin.name,
    vault_policy.identity-admin.name,
    vault_policy.oidc-config-admin.name,
  ]
}

resource "vault_identity_group_member_entity_ids" "tofu-runner" {
  group_id = vault_identity_group.tofu-runner.id
  member_entity_ids = [vault_identity_entity.tofu-runner.id]
}