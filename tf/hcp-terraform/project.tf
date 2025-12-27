// project.tf - HCP Terraform project for main-cluster workspaces

resource "tfe_project" "main_cluster" {
  name         = "main-cluster"
  organization = var.organization
  description  = "Self-hosted Kubernetes cluster infrastructure management"
}
