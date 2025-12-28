# tf/vault/jwt-hcp-terraform.tf
# HCP Terraform workload identity authentication.
#
# This JWT auth backend allows HCP Terraform to authenticate to Vault
# using workload identity (OIDC tokens). When Terraform runs execute,
# HCP Terraform provides a signed JWT that Vault validates against
# HCP Terraform's OIDC discovery endpoint.
#
# Flow: Terraform run starts -> HCP Terraform issues JWT ->
#       Vault validates JWT via OIDC discovery -> Returns Vault token ->
#       Terraform uses token for Vault provider operations

resource "vault_jwt_auth_backend" "hcp_terraform" {
  path               = "jwt-hcp-terraform"
  type               = "jwt"
  oidc_discovery_url = "https://app.terraform.io"
  bound_issuer       = "https://app.terraform.io"
  description        = "HCP Terraform workload identity for dynamic credentials"
}

resource "vault_jwt_auth_backend_role" "tfc_vault" {
  backend   = vault_jwt_auth_backend.hcp_terraform.path
  role_name = "tfc-vault"

  bound_audiences = ["vault.workload.identity"]
  bound_claims = {
    sub = "organization:fzymgc-house:project:main-cluster:workspace:main-cluster-vault:run_phase:*"
  }
  bound_claims_type = "glob" # Enable wildcard matching for run_phase:*

  user_claim     = "terraform_workspace_name"
  role_type      = "jwt"
  token_ttl      = 3600 # 1 hour for long-running applies
  token_max_ttl  = 7200 # 2 hour max for complex infrastructure changes
  token_policies = ["terraform-vault-admin"]
}

resource "vault_jwt_auth_backend_role" "tfc_authentik" {
  backend   = vault_jwt_auth_backend.hcp_terraform.path
  role_name = "tfc-authentik"

  bound_audiences = ["vault.workload.identity"]
  bound_claims = {
    sub = "organization:fzymgc-house:project:main-cluster:workspace:main-cluster-authentik:run_phase:*"
  }
  bound_claims_type = "glob" # Enable wildcard matching for run_phase:*

  user_claim     = "terraform_workspace_name"
  role_type      = "jwt"
  token_ttl      = 3600 # 1 hour for long-running applies
  token_max_ttl  = 7200 # 2 hour max for complex infrastructure changes
  token_policies = ["terraform-authentik-admin"]
}

resource "vault_jwt_auth_backend_role" "tfc_grafana" {
  backend   = vault_jwt_auth_backend.hcp_terraform.path
  role_name = "tfc-grafana"

  bound_audiences = ["vault.workload.identity"]
  bound_claims = {
    sub = "organization:fzymgc-house:project:main-cluster:workspace:main-cluster-grafana:run_phase:*"
  }
  bound_claims_type = "glob" # Enable wildcard matching for run_phase:*

  user_claim     = "terraform_workspace_name"
  role_type      = "jwt"
  token_ttl      = 3600 # 1 hour for long-running applies
  token_max_ttl  = 7200 # 2 hour max for complex infrastructure changes
  token_policies = ["terraform-grafana-admin"]
}

resource "vault_jwt_auth_backend_role" "tfc_cloudflare" {
  backend   = vault_jwt_auth_backend.hcp_terraform.path
  role_name = "tfc-cloudflare"

  bound_audiences = ["vault.workload.identity"]
  bound_claims = {
    sub = "organization:fzymgc-house:project:main-cluster:workspace:main-cluster-cloudflare:run_phase:*"
  }
  bound_claims_type = "glob" # Enable wildcard matching for run_phase:*

  user_claim     = "terraform_workspace_name"
  role_type      = "jwt"
  token_ttl      = 3600 # 1 hour for long-running applies
  token_max_ttl  = 7200 # 2 hour max for complex infrastructure changes
  token_policies = ["terraform-cloudflare-admin"]
}

resource "vault_jwt_auth_backend_role" "tfc_core_services" {
  backend   = vault_jwt_auth_backend.hcp_terraform.path
  role_name = "tfc-core-services"

  bound_audiences = ["vault.workload.identity"]
  bound_claims = {
    sub = "organization:fzymgc-house:project:main-cluster:workspace:main-cluster-core-services:run_phase:*"
  }
  bound_claims_type = "glob" # Enable wildcard matching for run_phase:*

  user_claim     = "terraform_workspace_name"
  role_type      = "jwt"
  token_ttl      = 3600 # 1 hour for long-running applies
  token_max_ttl  = 7200 # 2 hour max for complex infrastructure changes
  token_policies = ["terraform-core-services-admin"]
}

resource "vault_jwt_auth_backend_role" "tfc_hcp_terraform" {
  backend   = vault_jwt_auth_backend.hcp_terraform.path
  role_name = "tfc-hcp-terraform"

  bound_audiences = ["vault.workload.identity"]
  bound_claims = {
    sub = "organization:fzymgc-house:project:main-cluster:workspace:hcp-terraform:run_phase:*"
  }
  bound_claims_type = "glob" # Enable wildcard matching for run_phase:*

  user_claim     = "terraform_workspace_name"
  role_type      = "jwt"
  token_ttl      = 3600 # 1 hour for long-running applies
  token_max_ttl  = 7200 # 2 hour max for complex infrastructure changes
  token_policies = ["terraform-hcp-terraform"]
}

# Note: cluster-bootstrap workspace intentionally excluded from OIDC authentication.
# It deploys the HCP Terraform Operator itself (circular dependency), so must be
# run locally with VAULT_TOKEN environment variable.
