data "vault_pki_secret_backend_issuer" "fzymgc" {
  backend    = "fzymgc-house/v1/ica1/v1"
  issuer_ref = "d2c70b5d-8125-d217-f0a1-39289a096df2"
}

locals {
  grafana_ca_cert = join("\n", data.vault_pki_secret_backend_issuer.fzymgc.ca_chain)
}


provider "grafana" {
  url     = var.grafana_url
  auth    = var.grafana_api_key
  ca_cert = local.grafana_ca_cert
}
