import {
  id = "mealie"
  to = vault_policy.mealie
}

resource "vault_policy" "mealie" {
  name   = "mealie"
  policy = <<EOT
path "secret/data/fzymgc-house/cluster/mealie" {
  capabilities = ["read", "list"]
  description  = "Allow Mealie to read app configuration"
}

path "secret/data/fzymgc-house/cluster/postgres/users/main-mealie" {
  capabilities = ["read"]
  description  = "Allow Mealie to read database credentials"
}
EOT
}
