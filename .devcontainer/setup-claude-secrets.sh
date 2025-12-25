#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Verify MCP server API keys are available from Vault via direnv
#
# This script checks that the .envrc has loaded API keys from Vault.
# Secrets are fetched automatically by direnv when entering the directory.
#
# Claude Code uses interactive OAuth login (claude login), not API keys.
#
# Prerequisites:
#   1. Create Vault token on host: .devcontainer/create-vault-token.sh
#   2. Authenticate in container: vault login token=<token>
#   3. Run: direnv allow
#
# Exit codes:
#   0 - Success (MCP keys checked)
#   2 - Vault authentication skipped (not logged in)
#   1 - Error (direnv not working, etc.)

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Vault configuration
VAULT_ADDR="${VAULT_ADDR:-https://vault.fzymgc.house}"
export VAULT_ADDR

# Check if Vault CLI is available
if ! command -v vault &> /dev/null; then
    log_error "Vault CLI not found."
    exit 1
fi

# Check Vault authentication
if ! vault token lookup &> /dev/null; then
    log_warn "Not authenticated to Vault. Skipping MCP key setup."
    echo ""
    echo "To set up MCP server API keys:"
    echo "  1. On HOST: .devcontainer/create-vault-token.sh"
    echo "  2. In container: vault login token=<token>"
    echo "  3. Run: direnv allow"
    echo ""
    exit 2
fi

# Ensure direnv is allowed
if command -v direnv &> /dev/null; then
    direnv allow . 2>/dev/null || true
fi

# Check Claude Code login status
if [[ -f "${HOME}/.claude.json" ]]; then
    log_info "Claude Code: Logged in"
else
    log_warn "Claude Code: Not logged in (run: claude login)"
fi

# Check MCP keys (loaded via direnv from .envrc)
MCP_COUNT=0
echo ""
echo "MCP Server API Keys:"

if [[ -n "${FIRECRAWL_API_KEY:-}" ]]; then
    ((MCP_COUNT++))
    log_info "  Firecrawl: configured"
else
    log_warn "  Firecrawl: not configured (optional)"
fi

if [[ -n "${EXA_API_KEY:-}" ]]; then
    ((MCP_COUNT++))
    log_info "  Exa: configured"
else
    log_warn "  Exa: not configured (optional)"
fi

if [[ -n "${NOTION_API_KEY:-}" ]]; then
    ((MCP_COUNT++))
    log_info "  Notion: configured"
else
    log_warn "  Notion: not configured (optional)"
fi

echo ""
if [[ $MCP_COUNT -gt 0 ]]; then
    log_info "MCP server API keys: ${MCP_COUNT}/3 configured"
else
    log_info "MCP server API keys: none configured"
    echo ""
    echo "To add MCP keys, store them in Vault:"
    # Get entity name for helpful output
    ENTITY_NAME=""
    TOKEN_LOOKUP=$(vault token lookup -format=json 2>/dev/null) || true
    ENTITY_ID=$(echo "$TOKEN_LOOKUP" | jq -r '.data.entity_id // empty' 2>/dev/null) || true
    if [[ -n "${ENTITY_ID:-}" ]]; then
        ENTITY_NAME=$(vault read -format=json "identity/entity/id/${ENTITY_ID}" 2>/dev/null | jq -r '.data.name // empty') || true
    fi
    if [[ -z "${ENTITY_NAME:-}" ]]; then
        DISPLAY_NAME=$(echo "$TOKEN_LOOKUP" | jq -r '.data.display_name // empty' 2>/dev/null) || true
        ENTITY_NAME="${DISPLAY_NAME#github-}"
        ENTITY_NAME="${ENTITY_NAME#oidc-}"
    fi
    echo "  vault kv put secret/users/${ENTITY_NAME:-<username>}/firecrawl api_key=fc-..."
    echo "  vault kv put secret/users/${ENTITY_NAME:-<username>}/exa api_key=..."
    echo "  vault kv put secret/users/${ENTITY_NAME:-<username>}/notion api_key=secret_..."
    echo ""
    echo "Then reload: direnv allow"
fi
