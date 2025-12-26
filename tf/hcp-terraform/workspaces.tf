// workspaces.tf - Workspace configuration

locals {
  all_workspaces = {
    vault = {
      dir  = "tf/vault"
      tags = ["main-cluster", "vault"]
    }
    authentik = {
      dir  = "tf/authentik"
      tags = ["main-cluster", "authentik"]
    }
    grafana = {
      dir  = "tf/grafana"
      tags = ["main-cluster", "grafana"]
    }
    cloudflare = {
      dir  = "tf/cloudflare"
      tags = ["main-cluster", "cloudflared"]
    }
    core-services = {
      dir  = "tf/core-services"
      tags = ["main-cluster", "core-services"]
    }
    cluster-bootstrap = {
      dir  = "tf/cluster-bootstrap"
      tags = ["main-cluster", "bootstrap"]
    }
  }
}

resource "tfe_workspace" "this" {
  for_each = local.all_workspaces

  name              = each.key
  organization      = var.organization
  working_directory = each.value.dir
  tag_names         = each.value.tags

  # VCS-driven workflow
  auto_apply            = true
  speculative_enabled   = true
  file_triggers_enabled = true

  vcs_repo {
    identifier     = var.github_repo
    branch         = "main"
    oauth_token_id = data.tfe_oauth_client.github.oauth_token_id
  }
}

resource "tfe_workspace_settings" "this" {
  for_each = local.all_workspaces

  workspace_id   = tfe_workspace.this[each.key].id
  execution_mode = "agent"
  agent_pool_id  = tfe_agent_pool.main.id
}
