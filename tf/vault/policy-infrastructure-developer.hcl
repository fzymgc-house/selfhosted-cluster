# Policy: infrastructure-developer
# Purpose: Allow developers to read infrastructure secrets for Ansible and Terraform
# Usage: Attach this policy to developer tokens for running Ansible playbooks and Terraform modules
#
# To create this policy in Vault:
#   vault policy write infrastructure-developer policy-infrastructure-developer.hcl
#
# To attach to a token:
#   vault token create -policy=infrastructure-developer

# Read infrastructure secrets (BMC passwords, API tokens, etc.)
path "secret/data/fzymgc-house/infrastructure/*" {
  capabilities = ["read", "list"]
}

# List infrastructure secret paths
path "secret/metadata/fzymgc-house/infrastructure/*" {
  capabilities = ["list"]
}

# Read application secrets (used by Terraform for service configuration)
path "secret/data/fzymgc-house/*" {
  capabilities = ["read", "list"]
}

# List application secret paths
path "secret/metadata/fzymgc-house/*" {
  capabilities = ["list"]
}
