// organization.tf - HCP Terraform organization configuration
//
// Manages the organization settings including default Terraform version.

resource "tfe_organization" "this" {
  name  = var.organization
  email = var.organization_email

  # Default Terraform version for new workspaces
  default_project_id = tfe_project.main_cluster.id
}

# Import existing organization
import {
  to = tfe_organization.this
  id = var.organization
}
