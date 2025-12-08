# SPDX-License-Identifier: MIT

# Enable AppRole auth backend
resource "vault_auth_backend" "approle" {
  type            = "approle"
  disable_remount = false
}

# GitHub Actions AppRole for CI/CD workflows
resource "vault_approle_auth_backend_role" "github_actions" {
  backend        = vault_auth_backend.approle.path
  role_name      = "github-actions"
  token_policies = [vault_policy.github_actions.name]

  token_ttl     = 600  # 10 minutes
  token_max_ttl = 1800 # 30 minutes

  # Non-expiring for GitHub secrets storage
  secret_id_ttl      = 0
  secret_id_num_uses = 0
}
