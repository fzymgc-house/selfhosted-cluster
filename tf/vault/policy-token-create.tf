import {
  to = vault_policy.token-create
  id = "token-create"
}

resource "vault_policy" "token-create" {
  name   = "token-create"
  policy = <<EOT
# Allows the client to create child tokens
path "auth/token/create" {
  capabilities = ["create", "update"]
}

# Optionally allow creating orphan tokens
path "auth/token/create-orphan" {
  capabilities = ["create", "update"]
}

# Optionally allow reading the token's own info (useful for introspection)
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOT
}
