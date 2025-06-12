import {
  id = "ldap-config-admin"
  to = vault_policy.ldap-config-admin
}

resource "vault_policy" "ldap-config-admin" {
  name   = "ldap-config-admin"
  policy = <<EOT
# Full control over LDAP auth mount
path "auth/ldap/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "auth/ldap" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "auth" {
  capabilities = ["read", "list"]
}

# (Optional) If you want to enable or disable the mount itself
path "sys/auth/ldap" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

path "sys/auth" {
  capabilities = ["read", "list"]
}

path "sys/mounts/auth" {
  capabilities = ["read", "list"]
}

path "sys/mounts/auth/ldap" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}
EOT
}
