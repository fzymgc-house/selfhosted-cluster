// policy-terraform-workspaces.tf - Policies for HCP Terraform workspace OIDC auth

# Vault workspace - manages Vault configuration
resource "vault_policy" "terraform_vault_admin" {
  name   = "terraform-vault-admin"
  policy = <<EOT
# Manage auth methods
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Manage auth method configuration
path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

# Manage policies
path "sys/policies/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage identity entities and groups
path "identity/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Read secrets for configuration
path "secret/data/fzymgc-house/*" {
  capabilities = ["read", "list"]
}
EOT
}

# Authentik workspace - manages Authentik secrets
resource "vault_policy" "terraform_authentik_admin" {
  name   = "terraform-authentik-admin"
  policy = <<EOT
# Read Authentik secrets
path "secret/data/fzymgc-house/cluster/authentik" {
  capabilities = ["read", "list"]
}

# Read Authentik secret metadata
path "secret/metadata/fzymgc-house/cluster/authentik" {
  capabilities = ["read", "list"]
}
EOT
}

# Grafana workspace - manages Grafana secrets
resource "vault_policy" "terraform_grafana_admin" {
  name   = "terraform-grafana-admin"
  policy = <<EOT
# Read Grafana secrets
path "secret/data/fzymgc-house/cluster/grafana" {
  capabilities = ["read", "list"]
}

# Read Grafana secret metadata
path "secret/metadata/fzymgc-house/cluster/grafana" {
  capabilities = ["read", "list"]
}
EOT
}

# Cloudflare workspace - manages Cloudflare secrets
resource "vault_policy" "terraform_cloudflare_admin" {
  name   = "terraform-cloudflare-admin"
  policy = <<EOT
# Read Cloudflare secrets
path "secret/data/fzymgc-house/cluster/cloudflare" {
  capabilities = ["read", "list"]
}

# Read Cloudflare secret metadata
path "secret/metadata/fzymgc-house/cluster/cloudflare" {
  capabilities = ["read", "list"]
}
EOT
}

# Core-services workspace - manages core service secrets
resource "vault_policy" "terraform_core_services_admin" {
  name   = "terraform-core-services-admin"
  policy = <<EOT
# Read cluster secrets
path "secret/data/fzymgc-house/cluster/*" {
  capabilities = ["read", "list"]
}

# Read cluster secret metadata
path "secret/metadata/fzymgc-house/cluster/*" {
  capabilities = ["read", "list"]
}
EOT
}
