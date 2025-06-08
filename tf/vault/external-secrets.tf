import {
  id = "auth/kubernetes/role/external-secrets"
  to = vault_kubernetes_auth_backend_role.external-secrets
}

resource "vault_kubernetes_auth_backend_role" "external-secrets" {
  backend = vault_auth_backend.kubernetes.path
  role_name = "external-secrets"
  bound_service_account_namespaces = ["external-secrets"]
  bound_service_account_names = ["external-secrets-operator"]
  audience = "https://kubernetes.default.svc.cluster.local"
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
