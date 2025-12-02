import {
  id = "teleport"
  to = vault_policy.teleport
}

resource "vault_policy" "teleport" {
  name   = "teleport"
  policy = <<EOT
# Read Teleport secrets
path "secret/data/fzymgc-house/cluster/teleport/*" {
  capabilities = ["read"]
}

# List Teleport secrets metadata
path "secret/metadata/fzymgc-house/cluster/teleport/*" {
  capabilities = ["list"]
}
EOT
}
