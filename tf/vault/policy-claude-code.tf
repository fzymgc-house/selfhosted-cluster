# SPDX-License-Identifier: MIT-0
# Claude Code devcontainer policy
#
# Grants users access to their personal Anthropic API key stored in Vault.
# Each user stores their key at: secret/users/<entity-name>/anthropic
#
# This policy uses Vault templating to dynamically scope access based on
# the authenticated user's identity entity name.

resource "vault_policy" "claude_code" {
  name   = "claude-code"
  policy = <<-EOT
    # =============================================================================
    # Claude Code - Per-User Anthropic API Key Access
    # =============================================================================

    # Allow reading personal Anthropic API key
    # Path: secret/data/users/<entity-name>/anthropic
    # Key expected: api_key
    path "secret/data/users/{{identity.entity.name}}/anthropic" {
      capabilities = ["read"]
    }

    # Allow listing the user's secrets directory (for discoverability)
    path "secret/metadata/users/{{identity.entity.name}}/*" {
      capabilities = ["list"]
    }
  EOT
}
