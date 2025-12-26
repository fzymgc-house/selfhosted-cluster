// workspace-variables.tf - Workspace variables for Vault OIDC auth
//
// These variables configure each workspace to authenticate to Vault using
// HCP TF workload identity (OIDC JWT). When a run executes, HCP TF generates
// a signed JWT and writes it to a file. The Vault provider reads this file
// to authenticate.

# Workspaces that use Vault OIDC authentication
# Excludes cluster-bootstrap (runs locally with VAULT_TOKEN due to circular dependency)
locals {
  oidc_workspaces = {
    for k, v in local.all_workspaces : k => v
    if k != "cluster-bootstrap"
  }
}

# Vault address for all OIDC workspaces
resource "tfe_variable" "vault_addr" {
  for_each = local.oidc_workspaces

  workspace_id = tfe_workspace.this[each.key].id
  key          = "vault_addr"
  value        = "https://vault.fzymgc.house"
  category     = "terraform"
  description  = "Vault server address"
}

# Workload identity token file path
# HCP TF writes the JWT to this path when workload identity is configured
resource "tfe_variable" "tfc_workload_identity_token_path" {
  for_each = local.oidc_workspaces

  workspace_id = tfe_workspace.this[each.key].id
  key          = "tfc_workload_identity_token_path"
  value        = "/var/run/secrets/tfc/workload-identity-token"
  category     = "terraform"
  description  = "Path to HCP TF workload identity JWT"
}
