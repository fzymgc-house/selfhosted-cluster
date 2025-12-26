# SPDX-License-Identifier: MIT-0
# Claude Code devcontainer policy
#
# Grants users access to read and store their personal API keys/tokens in Vault:
# - Terraform Cloud (infrastructure state) - stored via login-setup.sh
# - Firecrawl (web scraping/search) - stored via login-setup.sh
# - Exa (deep research) - stored via login-setup.sh
# - Notion (workspace integration) - stored via login-setup.sh
#
# Note: Claude Code uses OAuth login (claude doctor), not API keys.
# The Anthropic path is retained for backwards compatibility (read-only).
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

    # Terraform Cloud token - stored via login-setup.sh, used to create credentials.tfrc.json
    path "secret/data/users/{{identity.entity.name}}/terraform-cloud" {
      capabilities = ["create", "read", "update"]
    }

    # MCP server API keys - stored via login-setup.sh
    # These are optional - Claude Code functions without them
    path "secret/data/users/{{identity.entity.name}}/firecrawl" {
      capabilities = ["create", "read", "update"]
    }

    path "secret/data/users/{{identity.entity.name}}/exa" {
      capabilities = ["create", "read", "update"]
    }

    path "secret/data/users/{{identity.entity.name}}/notion" {
      capabilities = ["create", "read", "update"]
    }

    # Allow listing the user's secrets directory (for discoverability)
    path "secret/metadata/users/{{identity.entity.name}}/*" {
      capabilities = ["list"]
    }
  EOT
}
