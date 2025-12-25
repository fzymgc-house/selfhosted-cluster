# Devcontainer Claude Code Design

**Status:** Approved
**Date:** 2025-12-25
**Issue:** #360
**Author:** Claude (with Sean)

## Overview

Enable Claude Code CLI to run entirely within a devcontainer with full MCP server support, Vault-based secret management, and portable plugin configuration.

## Goals

- **Remote sessions** - Run Claude Code from remote servers/VMs with full functionality
- **Local isolation** - Sandboxed environment with container-specific configuration
- **Portability** - Reproducible setup across machines and users

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Devcontainer                                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Claude Code CLI                                 │   │
│  │  └── MCP Servers (in-container)                 │   │
│  │      ├── filesystem (npx)                       │   │
│  │      ├── kubernetes-mcp-server (npx)            │   │
│  │      ├── serena (uvx)                           │   │
│  │      ├── context7 (npx)                         │   │
│  │      ├── firecrawl-mcp (npx)                    │   │
│  │      ├── exa (npx)                              │   │
│  │      └── notion (npx)                           │   │
│  └─────────────────────────────────────────────────┘   │
│                          │                              │
│  post-create.sh ─────────┼──► Vault (fetch secrets)    │
│                          │                              │
│  Mounted: ~/.kube, ~/.ssh, ~/.1password                │
└─────────────────────────────────────────────────────────┘
```

## Components

### MCP Servers

| Server | Command | Purpose |
|--------|---------|---------|
| filesystem | npx | File operations (scoped to /workspace) |
| kubernetes-mcp-server | npx | Cluster queries (read-only) |
| serena | uvx | Semantic code operations |
| context7 | npx | Library documentation |
| firecrawl-mcp | npx | Web scraping |
| exa | npx | Web search/research |
| notion | npx | Workspace documentation |

**Excluded:** Chrome MCP (no browser in headless container)

### Vault Secrets Structure

| Path | Contents |
|------|----------|
| `secret/fzymgc-house/cluster/claude-code` | Shared MCP API keys (firecrawl, exa, notion) |
| `secret/fzymgc-house/users/<username>/claude-code` | Per-user Anthropic API key |

### Project-Local Configuration

```
.claude/
├── settings.json    # Project permissions and settings
├── plugins.json     # Plugin install manifest
└── mcp.json         # Container-aware MCP config (optional)
```

## Implementation

### 1. Dockerfile Changes

Add tools for MCP servers:

```dockerfile
# For Serena MCP server and fast code search
RUN apt-get update && apt-get install -y \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

# Install ast-grep for structural code search
RUN curl -fsSL https://raw.githubusercontent.com/ast-grep/ast-grep/main/install.sh | bash -s -- -y

# Install uv for fast Python package management
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/vscode/.bashrc
```

### 2. devcontainer.json Updates

Add Node.js feature and .claude mount:

```json
{
    "features": {
        "ghcr.io/devcontainers/features/node:1": {
            "version": "22"
        }
    },
    "mounts": [
        "source=${localWorkspaceFolder}/.claude,target=/home/vscode/.claude,type=bind"
    ],
    "containerEnv": {
        "CLAUDE_CONFIG_DIR": "/home/vscode/.claude"
    }
}
```

### 3. MCP Configuration

Updated `.mcp.json` with container paths:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
    },
    "kubernetes-mcp-server": {
      "command": "npx",
      "args": ["-y", "kubernetes-mcp-server@latest", "--read-only"],
      "env": {
        "KUBECONFIG": "/home/vscode/.kube/config"
      }
    },
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    },
    "firecrawl-mcp": {
      "command": "npx",
      "args": ["-y", "firecrawl-mcp"],
      "env": {
        "FIRECRAWL_API_KEY": "${FIRECRAWL_API_KEY}"
      }
    },
    "exa": {
      "command": "npx",
      "args": ["-y", "exa-mcp-server"],
      "env": {
        "EXA_API_KEY": "${EXA_API_KEY}"
      }
    },
    "notion": {
      "command": "npx",
      "args": ["-y", "@notionhq/notion-mcp-server"],
      "env": {
        "NOTION_API_KEY": "${NOTION_API_KEY}"
      }
    },
    "serena": {
      "command": "uvx",
      "args": ["--from", "serena-mcp", "serena"],
      "env": {
        "SERENA_CONFIG": "/workspace/.serena/config.json"
      }
    }
  }
}
```

### 4. Vault Policy

Create `tf/vault/policy-claude-code.tf`:

```hcl
resource "vault_policy" "claude_code" {
  name = "claude-code"

  policy = <<-EOT
    # Read shared MCP secrets
    path "secret/data/fzymgc-house/cluster/claude-code" {
      capabilities = ["read"]
    }

    # Read own user's Claude secrets (templated by GitHub username)
    path "secret/data/fzymgc-house/users/{{identity.entity.aliases.auth_github_*.name}}/claude-code" {
      capabilities = ["read"]
    }
  EOT
}
```

### 5. Secret Fetch Script

Add to `post-create.sh`:

```bash
setup_claude_secrets() {
    log_info "Setting up Claude Code secrets from Vault..."

    if ! vault token lookup &> /dev/null; then
        log_warn "Not authenticated to Vault - Claude secrets not configured"
        echo "After running 'vault login', execute: setup-claude-secrets"
        return 1
    fi

    local gh_user
    gh_user=$(gh api user --jq '.login' 2>/dev/null || echo "")

    if [[ -z "$gh_user" ]]; then
        log_warn "GitHub CLI not authenticated - cannot determine username"
        return 1
    fi

    local shared_secrets user_secrets
    shared_secrets=$(vault kv get -format=json secret/fzymgc-house/cluster/claude-code 2>/dev/null)
    user_secrets=$(vault kv get -format=json "secret/fzymgc-house/users/${gh_user}/claude-code" 2>/dev/null)

    {
        echo "export ANTHROPIC_API_KEY='$(echo "$user_secrets" | jq -r '.data.data.anthropic_api_key')'"
        echo "export FIRECRAWL_API_KEY='$(echo "$shared_secrets" | jq -r '.data.data.firecrawl_api_key')'"
        echo "export EXA_API_KEY='$(echo "$shared_secrets" | jq -r '.data.data.exa_api_key')'"
        echo "export NOTION_API_KEY='$(echo "$shared_secrets" | jq -r '.data.data.notion_api_key')'"
    } > /home/vscode/.claude-env

    chmod 600 /home/vscode/.claude-env
    grep -q 'source ~/.claude-env' /home/vscode/.bashrc || echo 'source ~/.claude-env' >> /home/vscode/.bashrc

    log_info "✓ Claude Code secrets configured"
}
```

Also create standalone `.devcontainer/setup-claude-secrets.sh` for re-running after Vault login.

### 6. Plugin Configuration

Create `.claude/plugins.json`:

```json
{
  "plugins": [
    "superpowers@superpowers-marketplace",
    "commit-commands@claude-code-plugins",
    "pr-review-toolkit@claude-code-plugins",
    "feature-dev@claude-code-plugins"
  ]
}
```

Create `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Edit(.devcontainer/**)",
      "Edit(ansible/**)",
      "Edit(tf/**)",
      "Edit(argocd/**)",
      "Bash(git:*)",
      "Bash(terraform:*)",
      "Bash(kubectl:*)",
      "Bash(ansible:*)"
    ]
  }
}
```

Add plugin install to `post-create.sh`:

```bash
install_claude_plugins() {
    if [[ -f ".claude/plugins.json" ]]; then
        log_info "Installing Claude plugins..."
        jq -r '.plugins[]' .claude/plugins.json | while read -r plugin; do
            claude plugins install "$plugin" 2>/dev/null || true
        done
        log_info "✓ Claude plugins installed"
    fi
}
```

## Files to Create/Modify

| File | Action |
|------|--------|
| `.devcontainer/Dockerfile` | Add ripgrep, ast-grep, uv |
| `.devcontainer/devcontainer.json` | Add Node.js feature, .claude mount |
| `.devcontainer/post-create.sh` | Add secret fetch, plugin install functions |
| `.devcontainer/setup-claude-secrets.sh` | New standalone secret fetch script |
| `.mcp.json` | Update with container-aware paths |
| `.claude/settings.json` | New project settings |
| `.claude/plugins.json` | New plugin manifest |
| `tf/vault/policy-claude-code.tf` | New Vault policy |

## Usage

### First-Time Setup

1. Open repository in VS Code
2. Select "Reopen in Container"
3. Wait for container build and post-create script
4. Run `vault login -method=github`
5. Run `gh auth login -p https -w`
6. Run `setup-claude-secrets` to fetch API keys
7. Run `claude` to start Claude Code

### Subsequent Sessions

Container preserves authentication state. Just run `claude` to start.

### Remote/Headless Usage

```bash
# Build and start container
docker compose -f .devcontainer/docker-compose.yml up -d

# Exec into container
docker exec -it selfhosted-cluster-devcontainer bash

# Authenticate and run Claude
vault login -method=github
gh auth login
setup-claude-secrets
claude
```

## Security Considerations

- API keys stored in Vault, not in container or config files
- Per-user Anthropic keys prevent usage tracking conflicts
- Templated Vault policy scopes access to own user's secrets
- `.claude-env` file has restrictive permissions (0600)
- MCP filesystem scoped to `/workspace` only

## Future Work

- Add CI/CD workflow for running Claude in container
- Consider pre-built container image for faster startup
- Add health check for MCP server connectivity
- Explore VS Code tunnel for remote browser access (Chrome MCP)
