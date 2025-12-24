# Vault data sources for Grafana secrets

data "vault_kv_secret_v2" "grafana" {
  mount = "secret"
  name  = "fzymgc-house/cluster/grafana"
}
