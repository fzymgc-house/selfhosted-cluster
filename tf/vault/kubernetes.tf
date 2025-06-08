data "vault_kubernetes_auth_backend_config" "kubernetes" {
  backend = "auth/kubernetes"
}
