// workspace-variables.tf - Workspace variables for Vault OIDC auth and Kubernetes access
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

  # Workspaces that need Kubernetes access (run in-cluster in HCP TF agent)
  k8s_workspaces = toset(["vault", "core-services"])
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
# HCP TF Operator mounts the JWT at this path when workload identity is configured.
# Path is defined by HCP Terraform Operator (tested with v2.7.0).
# See: https://developer.hashicorp.com/terraform/cloud-docs/agents/agent-pools
resource "tfe_variable" "tfc_workload_identity_token_path" {
  for_each = local.oidc_workspaces

  workspace_id = tfe_workspace.this[each.key].id
  key          = "tfc_workload_identity_token_path"
  value        = "/var/run/secrets/tfc/workload-identity-token"
  category     = "terraform"
  description  = "Path to HCP TF workload identity JWT (operator v2.7.0)"
}

# Empty kubeconfig path for in-cluster auth (agent pod uses ServiceAccount)
resource "tfe_variable" "kubeconfig_path" {
  for_each = local.k8s_workspaces

  workspace_id = tfe_workspace.this[each.key].id
  key          = "kubeconfig_path"
  value        = ""
  category     = "terraform"
  description  = "Empty for in-cluster auth in HCP TF agent"
}

resource "tfe_variable" "kubeconfig_context" {
  for_each = local.k8s_workspaces

  workspace_id = tfe_workspace.this[each.key].id
  key          = "kubeconfig_context"
  value        = ""
  category     = "terraform"
  description  = "Empty for in-cluster auth in HCP TF agent"
}
