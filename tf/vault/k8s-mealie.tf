resource "vault_kubernetes_auth_backend_role" "mealie" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "mealie"
  bound_service_account_names      = ["default"]
  bound_service_account_namespaces = ["mealie"]
  audience                         = "https://kubernetes.default.svc.cluster.local"
  token_ttl                        = 3600
  token_policies                   = ["default", vault_policy.mealie.name]
}
