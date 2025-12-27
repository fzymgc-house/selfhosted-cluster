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

# Store agent token in Vault for Kubernetes operator to consume
resource "vault_kv_secret_v2" "hcp_terraform_agent" {
  mount = "secret"
  name  = "fzymgc-house/cluster/hcp-terraform"

  data_json = jsonencode({
    agent_token = tfe_agent_token.k8s.token
  })

  custom_metadata {
    max_versions = 3
    data = {
      managed_by = "terraform"
      module     = "tf/hcp-terraform"
    }
  }
}
