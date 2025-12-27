// policy-hcp-terraform.tf - Vault policy for HCP Terraform workspace
//
// Access to notification configuration secrets and agent token storage.
// Used by tf/hcp-terraform to configure Discord notifications and store agent credentials.

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

  # Write agent token for Kubernetes operator to consume
  rule {
    path         = "secret/data/fzymgc-house/cluster/hcp-terraform"
    capabilities = ["create", "update", "read", "delete"]
    description  = "Store HCP Terraform agent token for K8s operator"
  }

  rule {
    path         = "secret/metadata/fzymgc-house/cluster/hcp-terraform"
    capabilities = ["read", "delete"]
    description  = "Manage metadata for agent token secret"
  }
}

resource "vault_policy" "hcp_terraform" {
  name   = "terraform-hcp-terraform"
  policy = data.vault_policy_document.hcp_terraform.hcl
}
