// data.tf - Data sources for existing resources

data "tfe_oauth_client" "github" {
  organization     = var.organization
  service_provider = "github"
}
