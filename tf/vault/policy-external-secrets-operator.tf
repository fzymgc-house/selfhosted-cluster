
import {
  to = vault_policy.external-secrets-operator
  id = "external-secrets-operator"
}

resource "vault_policy" "external-secrets-operator" {
  name   = "external-secrets-operator"
  policy = <<EOT
path "secret/data" {
  capabilities = ["read","list"]
}

path "secret/data/*" {
  capabilities = ["read","list"]
}
EOT
}
