// agent_pool.tf - HCP Terraform Operator configuration
//
// The HCP Terraform Operator manages agent pools and tokens via the AgentPool CRD.
// This module only provides guidance - agent pool lifecycle is managed by the operator.
//
// See: argocd/app-configs/hcp-terraform-operator/

# Note: The HCP Terraform API token must be created manually in HCP Terraform UI:
# User Settings -> Tokens -> Create an API token
# Then stored in Vault using:
#   vault kv put secret/fzymgc-house/cluster/hcp-terraform api_token="<token>"
#
# The operator uses this token to create/manage agent pools and agent tokens.
