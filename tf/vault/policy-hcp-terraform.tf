// policy-hcp-terraform.tf - Vault policy for HCP Terraform workspace
//
// Read-only access to notification configuration secrets.
// Used by tf/hcp-terraform to configure Discord notifications.

data "vault_policy_document" "hcp_terraform" {
  # Read notification secrets (created by tf/vault and tf/cloudflare)
  rule {
    path         = "secret/data/fzymgc-house/infrastructure/cloudflare/hcp-terraform-hmac"
    capabilities = ["read"]
    description  = "Read HMAC token for notification signature verification"
  }

  rule {
    path         = "secret/data/fzymgc-house/infrastructure/cloudflare/hcp-terraform-worker"
    capabilities = ["read"]
    description  = "Read Worker URL for notification destination"
  }
}

resource "vault_policy" "hcp_terraform" {
  name   = "terraform-hcp-terraform"
  policy = data.vault_policy_document.hcp_terraform.hcl
}
