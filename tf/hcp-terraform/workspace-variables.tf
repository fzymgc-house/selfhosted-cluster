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
    if k != "main-cluster-bootstrap"
  }

  # Workspaces that need Kubernetes access (run in-cluster in HCP TF agent)
  k8s_workspaces = toset(["main-cluster-vault", "main-cluster-core-services"])
}

# =============================================================================
# Self-configuration: OIDC variables for the hcp-terraform workspace itself
# =============================================================================

# Reference to this workspace (self-managed via terraform cloud block)
data "tfe_workspace" "self" {
  name         = "hcp-terraform"
  organization = var.organization
}

# Vault address for this workspace (runs in local mode, uses VAULT_TOKEN)
resource "tfe_variable" "self_vault_addr" {
  workspace_id = data.tfe_workspace.self.id
  key          = "vault_addr"
  value        = "https://vault.fzymgc.house"
  category     = "terraform"
  description  = "Vault server address"
}

# Note: hcp-terraform workspace runs in local mode (not agent) due to circular
# dependency - it manages the agent pool configuration itself. Auth via VAULT_TOKEN.

# =============================================================================
# Vault Dynamic Credentials
# HCP TF handles JWT auth to Vault and injects tfc_vault_dynamic_credentials var
# See: https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/vault-configuration
# =============================================================================

resource "tfe_variable" "vault_provider_auth" {
  for_each = local.oidc_workspaces

  workspace_id = tfe_workspace.this[each.key].id
  key          = "TFC_VAULT_PROVIDER_AUTH"
  value        = "true"
  category     = "env"
  description  = "Enable dynamic Vault credentials"
}

resource "tfe_variable" "vault_addr" {
  for_each = local.oidc_workspaces

  workspace_id = tfe_workspace.this[each.key].id
  key          = "TFC_VAULT_ADDR"
  value        = "https://vault.fzymgc.house"
  category     = "env"
  description  = "Vault server address for dynamic credentials"
}

resource "tfe_variable" "vault_auth_path" {
  for_each = local.oidc_workspaces

  workspace_id = tfe_workspace.this[each.key].id
  key          = "TFC_VAULT_AUTH_PATH"
  value        = "jwt-hcp-terraform"
  category     = "env"
  description  = "Vault JWT auth backend path"
}

# Workspace-specific Vault role (tfc-vault, tfc-authentik, etc.)
resource "tfe_variable" "vault_run_role" {
  for_each = local.oidc_workspaces

  workspace_id = tfe_workspace.this[each.key].id
  key          = "TFC_VAULT_RUN_ROLE"
  value        = "tfc-${each.value.tags[1]}"  # e.g., tfc-vault, tfc-authentik
  category     = "env"
  description  = "Vault role for this workspace"
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
