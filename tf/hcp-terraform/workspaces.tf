// workspaces.tf - Workspace configuration

locals {
  # Workspace names match existing HCP Terraform workspaces
  # These already exist with state - we're adding them to a project
  all_workspaces = {
    main-cluster-vault = {
      dir  = "tf/vault"
      tags = ["main-cluster", "vault"]
    }
    main-cluster-authentik = {
      dir  = "tf/authentik"
      tags = ["main-cluster", "authentik"]
    }
    main-cluster-grafana = {
      dir  = "tf/grafana"
      tags = ["main-cluster", "grafana"]
    }
    main-cluster-cloudflare = {
      dir  = "tf/cloudflare"
      tags = ["main-cluster", "cloudflare"]
    }
    main-cluster-core-services = {
      dir  = "tf/core-services"
      tags = ["main-cluster", "core-services"]
    }
    main-cluster-bootstrap = {
      dir  = "tf/cluster-bootstrap"
      tags = ["main-cluster", "bootstrap"]
    }
  }
}

resource "tfe_workspace" "this" {
  for_each = local.all_workspaces

  name              = each.key
  organization      = var.organization
  project_id        = tfe_project.main_cluster.id
  working_directory = each.value.dir
  tag_names         = each.value.tags
  terraform_version = "~> 1.14.0"

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

# Look up the agent pool created by the HCP Terraform Kubernetes Operator
data "tfe_agent_pool" "k8s" {
  name         = "fzymgc-house-k8s"
  organization = var.organization
}

resource "tfe_workspace_settings" "this" {
  for_each = local.all_workspaces

  workspace_id   = tfe_workspace.this[each.key].id
  execution_mode = "agent"
  agent_pool_id  = data.tfe_agent_pool.k8s.id
}

# Settings for the hcp-terraform workspace itself (self-managed)
# Uses data.tfe_workspace.self defined in workspace-variables.tf
# MUST use local execution - this workspace manages the agent pool itself,
# so using agents would create a circular dependency (same as cluster-bootstrap)
resource "tfe_workspace_settings" "self" {
  workspace_id   = data.tfe_workspace.self.id
  execution_mode = "local"
}

# Import existing workspace settings (one-time operation)
import {
  to = tfe_workspace_settings.self
  id = "${var.organization}/hcp-terraform"
}
