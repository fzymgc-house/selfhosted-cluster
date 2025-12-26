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
