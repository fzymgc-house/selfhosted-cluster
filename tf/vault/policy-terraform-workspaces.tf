// policy-terraform-workspaces.tf - Policies for HCP Terraform workspace OIDC auth

# Vault workspace - manages Vault configuration (auth methods, policies, identity).
# This workspace does NOT need secret access - it only manages Vault infrastructure.
# Auth backends are restricted to specific paths to prevent privilege escalation.
resource "vault_policy" "terraform_vault_admin" {
  name   = "terraform-vault-admin"
  policy = <<EOT
# Manage specific auth backends (no wildcard, no sudo)
# Kubernetes auth backend
path "auth/kubernetes/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# AppRole auth backend
path "auth/approle/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# JWT auth backend for HCP Terraform
path "auth/jwt-hcp-terraform/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# OIDC auth backend (read-only for group aliases)
path "auth/oidc/*" {
  capabilities = ["read", "list"]
}

# Auth method mount/unmount (specific backends only, no sudo)
path "sys/auth/kubernetes" {
  capabilities = ["create", "read", "update", "delete"]
}
path "sys/auth/approle" {
  capabilities = ["create", "read", "update", "delete"]
}
path "sys/auth/jwt-hcp-terraform" {
  capabilities = ["create", "read", "update", "delete"]
}

# List auth methods (read-only discovery)
path "sys/auth" {
  capabilities = ["read", "list"]
}

# Manage policies
path "sys/policies/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage identity entities and groups
path "identity/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOT
}

# Authentik workspace - manages Authentik secrets and writes OIDC configs
resource "vault_policy" "terraform_authentik_admin" {
  name   = "terraform-authentik-admin"
  policy = <<EOT
# Read Authentik secrets
path "secret/data/fzymgc-house/cluster/authentik" {
  capabilities = ["read", "list"]
}

# Write OIDC credentials for applications managed by Authentik
path "secret/data/fzymgc-house/cluster/argocd/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/data/fzymgc-house/cluster/grafana" {
  capabilities = ["create", "read", "update", "delete"]
}
path "secret/data/fzymgc-house/cluster/vault/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/data/fzymgc-house/cluster/argo-workflows/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/data/fzymgc-house/cluster/mealie" {
  capabilities = ["create", "read", "update", "delete"]
}

# Metadata access
path "secret/metadata/fzymgc-house/cluster/authentik" {
  capabilities = ["read", "list"]
}
path "secret/metadata/fzymgc-house/cluster/argocd/*" {
  capabilities = ["read", "list", "delete"]
}
path "secret/metadata/fzymgc-house/cluster/grafana" {
  capabilities = ["read", "list", "delete"]
}
path "secret/metadata/fzymgc-house/cluster/vault/*" {
  capabilities = ["read", "list", "delete"]
}
path "secret/metadata/fzymgc-house/cluster/argo-workflows/*" {
  capabilities = ["read", "list", "delete"]
}
path "secret/metadata/fzymgc-house/cluster/mealie" {
  capabilities = ["read", "list", "delete"]
}
EOT
}

# Grafana workspace - manages Grafana secrets and MCP service account tokens
resource "vault_policy" "terraform_grafana_admin" {
  name   = "terraform-grafana-admin"
  policy = <<EOT
# Read Grafana secrets
path "secret/data/fzymgc-house/cluster/grafana" {
  capabilities = ["read", "list"]
}

# Write MCP service account tokens
path "secret/data/fzymgc-house/cluster/grafana/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Read PKI issuer for CA chain (required by Grafana provider)
path "fzymgc-house/v1/ica1/v1/issuer/+" {
  capabilities = ["read"]
}

# Metadata access
path "secret/metadata/fzymgc-house/cluster/grafana" {
  capabilities = ["read", "list"]
}
path "secret/metadata/fzymgc-house/cluster/grafana/*" {
  capabilities = ["read", "list", "delete"]
}
EOT
}

# Cloudflare workspace - manages Cloudflare secrets and tunnel credentials
resource "vault_policy" "terraform_cloudflare_admin" {
  name   = "terraform-cloudflare-admin"
  policy = <<EOT
# Read Cloudflare API token from infrastructure secrets
path "secret/data/fzymgc-house/infrastructure/cloudflare/*" {
  capabilities = ["read", "list"]
}

# Write tunnel credentials
path "secret/data/fzymgc-house/cluster/cloudflared/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Metadata access
path "secret/metadata/fzymgc-house/infrastructure/cloudflare/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/fzymgc-house/cluster/cloudflared/*" {
  capabilities = ["read", "list", "delete"]
}
EOT
}

# Core-services workspace - manages cross-cutting service configurations.
# This workspace configures shared infrastructure (ingress, cert-manager, etc.)
# and needs read access to multiple service secrets for configuration.
resource "vault_policy" "terraform_core_services_admin" {
  name   = "terraform-core-services-admin"
  policy = <<EOT
# Read cluster secrets (cross-cutting configuration needs)
path "secret/data/fzymgc-house/cluster/*" {
  capabilities = ["read", "list"]
}

# Read cluster secret metadata
path "secret/metadata/fzymgc-house/cluster/*" {
  capabilities = ["read", "list"]
}
EOT
}
