#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Fetch Anthropic API key from Vault for Claude Code
#
# This script retrieves the user's personal Anthropic API key from Vault
# and configures it for Claude Code. Users must first store their key:
#   vault kv put secret/users/<username>/anthropic api_key=sk-ant-...
#
# The claude-code policy allows each user to read only their own secrets.

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
    echo -e "${RED}[ERROR]${NC} $1"
}

# Vault configuration
VAULT_ADDR="${VAULT_ADDR:-https://vault.fzymgc.house}"
export VAULT_ADDR

# Check if Vault CLI is available
if ! command -v vault &> /dev/null; then
    log_error "Vault CLI not found. Cannot fetch Anthropic API key."
    exit 1
fi

# Check Vault authentication
if ! vault token lookup &> /dev/null; then
    log_warn "Not authenticated to Vault. Skipping Anthropic API key setup."
    echo ""
    echo "To set up your Anthropic API key:"
    echo "  1. Authenticate to Vault: vault login -method=github"
    echo "  2. Store your API key:    vault kv put secret/users/\$USER/anthropic api_key=sk-ant-..."
    echo "  3. Re-run this script:    bash .devcontainer/setup-claude-secrets.sh"
    echo ""
    exit 0
fi

# Get the entity name from Vault (this is what the templated policy uses)
ENTITY_NAME=$(vault token lookup -format=json 2>/dev/null | jq -r '.data.entity_id // empty')
if [[ -z "$ENTITY_NAME" ]]; then
    # Fallback to getting the entity name directly
    ENTITY_NAME=$(vault read -format=json identity/entity/id/"$(vault token lookup -format=json | jq -r '.data.entity_id')" 2>/dev/null | jq -r '.data.name // empty')
fi

# If we still don't have the entity name, try the display name or username
if [[ -z "$ENTITY_NAME" ]]; then
    ENTITY_NAME=$(vault token lookup -format=json 2>/dev/null | jq -r '.data.display_name // empty' | sed 's/github-//')
fi

if [[ -z "$ENTITY_NAME" ]]; then
    log_warn "Could not determine Vault entity name."
    echo "Please ensure you have an entity configured in Vault."
    exit 0
fi

log_info "Checking for Anthropic API key for entity: $ENTITY_NAME"

# Try to fetch the API key from Vault
SECRET_PATH="secret/users/${ENTITY_NAME}/anthropic"
API_KEY=$(vault kv get -format=json "$SECRET_PATH" 2>/dev/null | jq -r '.data.data.api_key // empty' || echo "")

if [[ -z "$API_KEY" ]]; then
    log_warn "No Anthropic API key found at ${SECRET_PATH}"
    echo ""
    echo "To store your Anthropic API key in Vault:"
    echo "  vault kv put ${SECRET_PATH} api_key=sk-ant-..."
    echo ""
    echo "Then re-run this script or start a new Claude Code session."
    exit 0
fi

log_info "Found Anthropic API key in Vault"

# Set the ANTHROPIC_API_KEY environment variable for the current session
# and add it to .bashrc for future sessions
BASHRC="${HOME}/.bashrc"
if ! grep -q "ANTHROPIC_API_KEY" "$BASHRC" 2>/dev/null; then
    {
        echo ""
        echo "# Anthropic API key for Claude Code (from Vault)"
        echo "export ANTHROPIC_API_KEY=\"$API_KEY\""
    } >> "$BASHRC"
    log_info "Added ANTHROPIC_API_KEY to ~/.bashrc"
else
    # Update existing entry
    sed -i "s/export ANTHROPIC_API_KEY=.*/export ANTHROPIC_API_KEY=\"$API_KEY\"/" "$BASHRC"
    log_info "Updated ANTHROPIC_API_KEY in ~/.bashrc"
fi

# Export for current session
export ANTHROPIC_API_KEY="$API_KEY"

log_info "Claude Code API key configured successfully"
echo ""
echo "The ANTHROPIC_API_KEY environment variable has been set."
echo "Claude Code will use this key for API calls."
