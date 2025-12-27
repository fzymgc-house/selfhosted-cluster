// organization.tf - HCP Terraform organization configuration
//
// Manages organization-level settings and defaults for new workspaces.

resource "tfe_organization" "this" {
  name  = var.organization
  email = var.organization_email
}

# Import existing organization
import {
  to = tfe_organization.this
  id = var.organization
}

# Organization-wide default settings for new workspaces
# All workspaces default to agent execution unless overridden
resource "tfe_organization_default_settings" "this" {
  organization           = var.organization
  default_execution_mode = "agent"
  default_agent_pool_id  = data.tfe_agent_pool.k8s.id
}

# Import existing default settings
import {
  to = tfe_organization_default_settings.this
  id = var.organization
}
