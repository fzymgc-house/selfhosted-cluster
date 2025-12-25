# SPDX-License-Identifier: MIT-0
# Claude Code devcontainer policy
#
# Grants users access to their personal API keys/tokens stored in Vault:
# - Terraform Cloud (infrastructure state)
# - Firecrawl (web scraping/search)
# - Exa (deep research)
# - Notion (workspace integration)
#
# Note: Claude Code uses OAuth login (claude doctor), not API keys.
# The Anthropic path is retained for backwards compatibility.
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

    # Anthropic API key path (retained for backwards compatibility)
    # Claude Code now uses OAuth login, but this path may still be used
    # by other tools or scripts that need the API key directly
    path "secret/data/users/{{identity.entity.name}}/anthropic" {
      capabilities = ["read"]
    }

    # Terraform Cloud token - used to create credentials.tfrc.json
    path "secret/data/users/{{identity.entity.name}}/terraform-cloud" {
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
