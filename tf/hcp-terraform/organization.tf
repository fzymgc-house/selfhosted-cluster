// organization.tf - HCP Terraform organization configuration
//
// Manages organization-level settings and defaults for new workspaces.
// This ensures organization settings are version-controlled and auditable.

resource "tfe_organization" "this" {
  name  = var.organization
  email = var.organization_email
}

# Organization-wide default settings for new workspaces
# Requires: Agent pool "fzymgc-house-k8s" must exist (created by HCP TF Operator)
# All new workspaces default to agent execution unless explicitly overridden
resource "tfe_organization_default_settings" "this" {
  organization           = var.organization
  default_execution_mode = "agent"
  default_agent_pool_id  = data.tfe_agent_pool.k8s.id
}

# -----------------------------------------------------------------------------
# Import blocks - for one-time import of existing resources
# NOTE: These can be removed after first successful terraform apply
# They serve as documentation that these resources were imported (not created)
# -----------------------------------------------------------------------------

import {
  to = tfe_organization.this
  id = var.organization
}

import {
  to = tfe_organization_default_settings.this
  id = var.organization
}
