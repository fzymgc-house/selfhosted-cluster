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

resource "vault_identity_group_member_entity_ids" "admin" {
  group_id = vault_identity_group.admin.id
  member_entity_ids = [vault_identity_entity.sean.id]
}

