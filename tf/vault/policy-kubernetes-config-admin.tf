import {
  id = "kubernetes-config-admin"
  to = vault_policy.kubernetes-config-admin
}

resource "vault_policy" "kubernetes-config-admin" {
  name   = "kubernetes-config-admin"
  policy = <<EOT
# Full control over Kubernetes auth mount
path "auth/kubernetes/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "auth/kubernetes" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "auth" {
  capabilities = ["read", "list"]
}

# (Optional) If you want to enable or disable the mount itself
path "sys/auth/kubernetes" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

path "sys/auth" {
  capabilities = ["read", "list"]
}

path "sys/mounts/auth" {
  capabilities = ["read", "list"]
}

path "sys/mounts/auth/kubernetes" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}
EOT
}

