import {
  id = "fzymgc-cluster-secret-reader"
  to = vault_policy.fzymgc_cluster_secret_reader
}

resource "vault_policy" "fzymgc_cluster_secret_reader" {
  name   = "fzymgc-cluster-secret-reader"
  policy = <<EOT
path "secret/data" {
  capabilities = ["read", "list"]
}

path "secret/data/*" {
  capabilities = ["read", "list"]
}
EOT
}
