import {
  id = "kubernetes"
  to = vault_auth_backend.kubernetes
}

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}