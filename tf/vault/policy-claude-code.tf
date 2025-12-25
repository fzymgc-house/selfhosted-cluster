# SPDX-License-Identifier: MIT-0
# Claude Code devcontainer policy
#
# Grants users access to their personal API keys stored in Vault:
# - Anthropic API key for Claude Code
# - MCP server API keys (Firecrawl, Exa, Notion)
#
# Each user stores their keys at: secret/users/<entity-name>/<service>
#
# This policy uses Vault templating to dynamically scope access based on
# the authenticated user's identity entity name.

resource "vault_policy" "claude_code" {
  name   = "claude-code"
  policy = <<-EOT
    # =============================================================================
    # Claude Code - Per-User API Key Access
    # =============================================================================

    # Allow reading personal Anthropic API key
    # Path: secret/data/users/<entity-name>/anthropic
    # Key expected: api_key
    path "secret/data/users/{{identity.entity.name}}/anthropic" {
      capabilities = ["read"]
    }

    # Allow reading MCP server API keys
    # These are optional - Claude Code functions without them
    path "secret/data/users/{{identity.entity.name}}/firecrawl" {
      capabilities = ["read"]
    }

    path "secret/data/users/{{identity.entity.name}}/exa" {
      capabilities = ["read"]
    }

    path "secret/data/users/{{identity.entity.name}}/notion" {
      capabilities = ["read"]
    }

    # Allow listing the user's secrets directory (for discoverability)
    path "secret/metadata/users/{{identity.entity.name}}/*" {
      capabilities = ["list"]
    }
  EOT
}
