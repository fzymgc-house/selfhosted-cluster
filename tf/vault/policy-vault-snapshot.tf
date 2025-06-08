import {
  to = vault_policy.vault-snapshot-read
  id = "vault-snapshot-read"
}

resource "vault_policy" "vault-snapshot-read" {
  name   = "vault-snapshot-read"
  policy = <<EOT
    path "sys/storage/raft/snapshot" {
      capabilities = ["read"]
    }
EOT
}
