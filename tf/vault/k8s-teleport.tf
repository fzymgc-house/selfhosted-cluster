# Kubernetes authentication role for Teleport
# Binds the teleport service account to the teleport policy

resource "vault_kubernetes_auth_backend_role" "teleport" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "teleport"
  bound_service_account_names      = ["teleport"]
  bound_service_account_namespaces = ["teleport"]
  token_policies                   = [vault_policy.teleport.name]
  token_ttl                        = 3600
}
