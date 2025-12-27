// outputs.tf - Output values

output "agent_pool_id" {
  description = "Agent pool ID for workspace configuration"
  value       = tfe_agent_pool.main.id
}

output "agent_token" {
  description = "Agent token for Kubernetes deployment (store in Vault)"
  value       = tfe_agent_token.k8s.token
  sensitive   = true
}
