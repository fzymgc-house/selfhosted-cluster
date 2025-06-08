import {
  id = "kubernetes"
  to = vault_auth_backend.kubernetes
}

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  disable_remount = false
}

import {
  id = "auth/kubernetes/config"
  to = vault_kubernetes_auth_backend_config.kubernetes
}

resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  backend = vault_auth_backend.kubernetes.path
  kubernetes_host = "https://kubernetes.default.svc"
}
