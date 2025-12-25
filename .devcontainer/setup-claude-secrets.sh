#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Verify API keys are available from Vault via direnv
#
# This script checks that the .envrc has loaded API keys from Vault.
# Secrets are fetched automatically by direnv when entering the directory.
#
# Prerequisites:
#   1. Authenticate to Vault: vault login -method=oidc
#   2. Store API keys in Vault (see .envrc for paths)
#   3. Run: direnv allow
#
# Exit codes:
#   0 - Success (ANTHROPIC_API_KEY is set)
#   2 - Vault authentication skipped (not logged in)
#   3 - Anthropic API key not found in Vault
#   1 - Error (direnv not working, etc.)

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

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
    log_warn "Not authenticated to Vault. Skipping API key setup."
    echo ""
    echo "To set up API keys:"
    echo "  1. Authenticate to Vault: vault login -method=oidc"
    echo "  2. Store your API keys (see .envrc for Vault paths)"
    echo "  3. Run: direnv allow"
    echo ""
    exit 2
fi

# Ensure direnv is allowed
if command -v direnv &> /dev/null; then
    direnv allow . 2>/dev/null || true
fi

# Check if ANTHROPIC_API_KEY is set (via direnv loading .envrc)
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    log_info "ANTHROPIC_API_KEY is set"
else
    # Try to get entity name to provide helpful guidance
    TOKEN_LOOKUP=$(vault token lookup -format=json 2>/dev/null) || true
    ENTITY_ID=$(echo "$TOKEN_LOOKUP" | jq -r '.data.entity_id // empty' 2>/dev/null) || true
    ENTITY_NAME=""

    if [[ -n "${ENTITY_ID:-}" ]]; then
        ENTITY_NAME=$(vault read -format=json "identity/entity/id/${ENTITY_ID}" 2>/dev/null | jq -r '.data.name // empty') || true
    fi
    if [[ -z "${ENTITY_NAME:-}" ]]; then
        DISPLAY_NAME=$(echo "$TOKEN_LOOKUP" | jq -r '.data.display_name // empty' 2>/dev/null) || true
        ENTITY_NAME="${DISPLAY_NAME#github-}"
        ENTITY_NAME="${ENTITY_NAME#oidc-}"
    fi

    log_warn "ANTHROPIC_API_KEY not found"
    echo ""
    echo "Store your Anthropic API key in Vault:"
    echo "  vault kv put secret/users/${ENTITY_NAME:-<username>}/anthropic api_key=sk-ant-..."
    echo ""
    echo "Then reload the environment:"
    echo "  direnv allow"
    echo ""
    exit 3
fi

# Check optional MCP keys
MCP_COUNT=0
[[ -n "${FIRECRAWL_API_KEY:-}" ]] && ((MCP_COUNT++)) && log_info "FIRECRAWL_API_KEY is set"
[[ -n "${EXA_API_KEY:-}" ]] && ((MCP_COUNT++)) && log_info "EXA_API_KEY is set"
[[ -n "${NOTION_API_KEY:-}" ]] && ((MCP_COUNT++)) && log_info "NOTION_API_KEY is set"

echo ""
log_info "Claude Code API key configured"
if [[ $MCP_COUNT -gt 0 ]]; then
    log_info "MCP server API keys: ${MCP_COUNT}/3 configured"
else
    log_info "MCP server API keys: none configured (optional)"
fi
