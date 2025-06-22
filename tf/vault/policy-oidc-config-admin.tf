import {
  id = "oidc-config-admin"
  to = vault_policy.oidc-config-admin
}

resource "vault_policy" "oidc-config-admin" {
  name   = "oidc-config-admin"
  policy = <<EOT
# Full control over OIDC auth mount
path "auth/oidc/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "auth/oidc" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "auth" {
  capabilities = ["read", "list"]
}

# (Optional) If you want to enable or disable the mount itself
path "sys/auth/oidc" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

path "sys/auth" {
  capabilities = ["read", "list"]
}

path "sys/mounts/auth" {
  capabilities = ["read", "list"]
}

path "sys/mounts/auth/oidc" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}
EOT
}
