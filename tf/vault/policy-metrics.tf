import {
  to = vault_policy.metrics
  id = "metrics"
}

resource "vault_policy" "metrics" {
  name   = "metrics"
  policy = <<EOT
path "secret/data/metrics" {
  capabilities = ["read","list"]
}
path "secret/data/metrics/*" {
  capabilities = ["read","list"]
}
EOT
}
