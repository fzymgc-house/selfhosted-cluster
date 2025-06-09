
resource "vault_kubernetes_auth_backend_role" "cert-manager" {
  backend = vault_auth_backend.kubernetes.path
  role_name = "cert-manager"
  bound_service_account_namespaces = ["cert-manager"]
  bound_service_account_names = ["cert-manager"]
  audience = "vault://vault"
  token_policies = ["default", "cert-manager"]
}
