#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Interactive setup for Vault, GitHub, Terraform, and Claude Code authentication
#
# Run this script after opening a terminal in the devcontainer to complete
# authentication setup for all services.

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_step() { echo -e "${BLUE}[→]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           Development Environment Login Setup              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Track what needs setup
needs_vault=false
needs_github=false
needs_terraform=false
needs_claude=false

# Check current auth status
echo "Checking authentication status..."
echo ""

# Vault (note: OIDC login requires localhost:8250 callback, doesn't work in container)
if vault token lookup &>/dev/null; then
    log_info "Vault: Authenticated"
else
    log_warn "Vault: Not authenticated (required for MCP server keys)"
    needs_vault=true
fi

# GitHub
if gh auth status &>/dev/null 2>&1; then
    log_info "GitHub CLI: Authenticated"
else
    log_warn "GitHub CLI: Not authenticated"
    needs_github=true
fi

# Terraform
if [[ -f "${HOME}/.terraform.d/credentials.tfrc.json" ]]; then
    log_info "Terraform Cloud: Credentials found"
else
    log_warn "Terraform Cloud: Not authenticated"
    needs_terraform=true
fi

# Claude (check for config file from 'claude login')
if [[ -f "${HOME}/.claude.json" ]]; then
    log_info "Claude Code: Logged in"
else
    log_warn "Claude Code: Not logged in"
    needs_claude=true
fi

# MCP servers (optional, requires Vault auth)
mcp_count=0
[[ -n "${FIRECRAWL_API_KEY:-}" ]] && ((mcp_count++))
[[ -n "${EXA_API_KEY:-}" ]] && ((mcp_count++))
[[ -n "${NOTION_API_KEY:-}" ]] && ((mcp_count++))
if [[ $mcp_count -gt 0 ]]; then
    log_info "MCP servers: ${mcp_count}/3 API keys configured"
else
    log_warn "MCP servers: No API keys configured (optional, requires Vault)"
fi

echo ""

# If everything is set up, exit early
if ! $needs_vault && ! $needs_github && ! $needs_terraform && ! $needs_claude; then
    echo "All services authenticated! You're ready to develop."
    exit 0
fi

echo "────────────────────────────────────────────────────────────────"
echo ""

# Step 1: Claude Code (interactive OAuth login)
if $needs_claude; then
    log_step "Step 1: Claude Code Authentication"
    echo "    Claude Code uses interactive OAuth login (opens browser)."
    echo ""
    read -p "    Run 'claude login'? [Y/n] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        claude login || {
            log_warn "Claude login failed. You can retry later with: claude login"
        }
    fi
    echo ""
fi

# Step 2: Vault (for MCP server API keys)
# Note: OIDC login requires localhost:8250 callback which doesn't work in container
if $needs_vault; then
    log_step "Step 2: Vault Authentication"
    echo "    Vault stores MCP server API keys (Firecrawl, Exa, Notion)."
    echo ""
    echo "    NOTE: Vault OIDC login requires localhost:8250 callback,"
    echo "    which doesn't work in devcontainers."
    echo ""
    echo "    Options:"
    echo "      1. Create a token on your HOST machine first:"
    echo "         ./scripts/create-vault-token.sh"
    echo "         (run from repository root on host)"
    echo ""
    echo "      2. Or paste an existing Vault token"
    echo ""
    read -p "    Do you have a Vault token to paste? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "    Paste your Vault token (it will be hidden):"
        read -rs VAULT_TOKEN_INPUT
        echo ""
        if [[ -n "$VAULT_TOKEN_INPUT" ]]; then
            if vault login token="$VAULT_TOKEN_INPUT" 2>/dev/null; then
                log_info "Vault authentication successful"
                needs_vault=false
            else
                log_warn "Vault token login failed. Check your token is valid."
            fi
        fi
    else
        echo ""
        echo "    To create a token, run on your HOST machine:"
        echo "      ./scripts/create-vault-token.sh"
        echo ""
        echo "    Then re-run this script to continue setup."
    fi
    echo ""
fi

# Step 2b: MCP server API keys (if Vault is authenticated)
if vault token lookup &>/dev/null; then
    # Get entity name for the secret path
    if ! TOKEN_LOOKUP=$(vault token lookup -format=json 2>&1); then
        log_warn "Failed to look up Vault token: ${TOKEN_LOOKUP}"
        TOKEN_LOOKUP=""
    fi
    ENTITY_ID=$(echo "$TOKEN_LOOKUP" | jq -r '.data.entity_id // empty' 2>/dev/null)

    if [[ -n "$ENTITY_ID" ]]; then
        if ! ENTITY_READ=$(vault read -format=json "identity/entity/id/${ENTITY_ID}" 2>&1); then
            log_warn "Could not read entity details: ${ENTITY_READ}"
            ENTITY_READ=""
        fi
        ENTITY_NAME=$(echo "$ENTITY_READ" | jq -r '.data.name // empty' 2>/dev/null)
    fi

    # Fallback to display_name
    if [[ -z "${ENTITY_NAME:-}" ]]; then
        DISPLAY_NAME=$(echo "$TOKEN_LOOKUP" | jq -r '.data.display_name // empty' 2>/dev/null)
        ENTITY_NAME="${DISPLAY_NAME#github-}"
        ENTITY_NAME="${ENTITY_NAME#oidc-}"
    fi

    if [[ -n "${ENTITY_NAME:-}" ]]; then
        # Helper function to prompt for API key storage
        prompt_api_key() {
            local service="$1"
            local secret_path="$2"
            local prefix="${3:-}"
            local step_num="$4"

            if vault kv get -format=json "$secret_path" &>/dev/null; then
                log_info "${service} API key found in Vault"
                return 0
            fi

            log_step "Step ${step_num}: ${service} API Key"
            echo "    Store your ${service} API key in Vault."
            echo "    Path: ${secret_path}"
            echo ""
            read -p "    Do you have a ${service} API key to store? [y/N] " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo ""
                if [[ -n "$prefix" ]]; then
                    echo "    Enter your ${service} API key (starts with ${prefix}):"
                else
                    echo "    Enter your ${service} API key:"
                fi
                read -rs API_KEY_INPUT
                echo ""
                if [[ -n "$API_KEY_INPUT" ]]; then
                    if vault kv put "$secret_path" api_key="$API_KEY_INPUT" &>/dev/null; then
                        log_info "${service} API key stored in Vault"
                    else
                        log_warn "Failed to store ${service} API key. Check your Vault permissions."
                    fi
                fi
            else
                echo ""
                echo "    You can store it later with:"
                echo "      vault kv put ${secret_path} api_key=..."
                echo ""
            fi
        }

        # MCP server API keys (optional)
        echo ""
        log_step "Step 2b: MCP Server API Keys (Optional)"
        echo "    These keys enable additional MCP server functionality."
        echo ""
        read -p "    Would you like to configure MCP server API keys? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo ""
            prompt_api_key "Firecrawl" "secret/users/${ENTITY_NAME}/firecrawl" "fc-" "2b.1"
            prompt_api_key "Exa" "secret/users/${ENTITY_NAME}/exa" "" "2b.2"
            prompt_api_key "Notion" "secret/users/${ENTITY_NAME}/notion" "secret_" "2b.3"
        fi

        # Reload direnv to pick up the new secrets
        echo ""
        log_info "Reloading environment to pick up API keys..."
        direnv allow . 2>/dev/null || true
        # Source the .envrc manually since we're in a script
        # shellcheck source=/dev/null
        source <(direnv export bash 2>/dev/null) || true
    fi
    echo ""
fi

# Step 3: GitHub CLI
if $needs_github; then
    log_step "Step 3: GitHub CLI Authentication"
    echo "    GitHub CLI is used for PR management and repository access."
    echo ""
    read -p "    Run 'gh auth login -p https -w'? [Y/n] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        gh auth login -p https -w || {
            log_warn "GitHub login failed. You can retry later with: gh auth login -p https -w"
        }
    fi
    echo ""
fi

# Step 4: Terraform Cloud
if $needs_terraform; then
    log_step "Step 4: Terraform Cloud Authentication"
    echo "    Terraform Cloud stores remote state for infrastructure."
    echo ""
    read -p "    Run 'terraform login'? [Y/n] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        terraform login || {
            log_warn "Terraform login failed. You can retry later with: terraform login"
        }
    fi
    echo ""
fi

echo "────────────────────────────────────────────────────────────────"
echo ""
echo "Setup complete! Run this script again to check status."
echo ""
