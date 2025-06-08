resource "vault_kubernetes_auth_backend_role" "external-secrets" {
  backend = data.vault_kubernetes_auth_backend_config.kubernetes.backend
  role_name = "external-secrets"
  bound_service_account_namespaces = ["external-secrets"]
  bound_service_account_names = ["external-secrets"]
  audience = "vault"
  token_policies = ["default", "external-secrets-operator"]
}

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
