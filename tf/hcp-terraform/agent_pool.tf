// agent_pool.tf - Agent pool and token configuration

resource "tfe_agent_pool" "main" {
  name                = "fzymgc-house-k8s"
  organization        = var.organization
  organization_scoped = true
}

resource "tfe_agent_token" "k8s" {
  agent_pool_id = tfe_agent_pool.main.id
  description   = "Kubernetes cluster agent"
}
