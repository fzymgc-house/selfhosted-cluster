import {
  id = "identity-admin"
  to = vault_policy.identity-admin
}

resource "vault_policy" "identity-admin" {
  name   = "identity-admin"
  policy = <<EOT
path "identity/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "identity" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

EOT
}
