# Vault secrets for Grafana configuration
#
# Using data source instead of ephemeral because:
# - Grafana provider doesn't support ephemeral values for all attributes yet
# - Discord webhook URL in contact_points.tf requires non-ephemeral value
#
# TODO(#341): Migrate to ephemeral when Grafana provider adds support

data "vault_kv_secret_v2" "grafana" {
  mount = "secret"
  name  = "fzymgc-house/cluster/grafana"
}
