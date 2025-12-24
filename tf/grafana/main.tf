data "vault_pki_secret_backend_issuer" "fzymgc" {
  backend    = "fzymgc-house/v1/ica1/v1"
  issuer_ref = "d2c70b5d-8125-d217-f0a1-39289a096df2"
}

locals {
  grafana_ca_cert = join("\n", data.vault_pki_secret_backend_issuer.fzymgc.ca_chain)
  grafana_url     = "https://grafana.fzymgc.house"
}


provider "grafana" {
  url     = local.grafana_url
  auth    = data.vault_kv_secret_v2.grafana.data["terraform_admin_api_token"]
  ca_cert = local.grafana_ca_cert
}
