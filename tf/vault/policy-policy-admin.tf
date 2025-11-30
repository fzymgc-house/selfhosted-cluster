import {
  to = vault_policy.policy-admin
  id = "policy-admin"
}

resource "vault_policy" "policy-admin" {
  name   = "policy-admin"
  policy = <<EOT
# Allow full management of Vault policies
path "sys/policy/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/policies/*" {
	capabilities = ["create", "read", "update", "delete", "list"]
}
EOT
}