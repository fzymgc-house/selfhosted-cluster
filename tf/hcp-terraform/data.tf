# data.tf - Data sources for existing resources

data "tfe_oauth_client" "github" {
  organization     = var.organization
  service_provider = "github"
}

# CA certificate chain for HCP TF to verify Vault's TLS certificate
# The fullchain contains both intermediate and root CA certificates
data "vault_kv_secret_v2" "ca_certificate" {
  mount = "secret"
  name  = "fzymgc-house/infrastructure/pki/fzymgc-ica1-ca"
}
