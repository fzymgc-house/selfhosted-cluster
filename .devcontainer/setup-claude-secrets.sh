#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Fetch Anthropic API key from Vault for Claude Code
#
# This script retrieves the user's personal Anthropic API key from Vault
# and configures it for Claude Code. Users must first store their key:
#   vault kv put secret/users/<entity-name>/anthropic api_key=sk-ant-...
#
# The entity name is determined from your Vault identity (typically your
# GitHub username when using GitHub auth). The claude-code policy allows
# each user to read only their own secrets.
#
# Exit codes:
#   0 - Success (API key configured)
#   2 - Vault authentication skipped (not logged in)
#   3 - API key not found in Vault
#   1 - Error (Vault CLI missing, command failure, etc.)

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
    log_error "Vault CLI not found. Cannot fetch Anthropic API key."
    exit 1
fi

# Check Vault authentication
if ! vault token lookup &> /dev/null; then
    log_warn "Not authenticated to Vault. Skipping Anthropic API key setup."
    echo ""
    echo "To set up your Anthropic API key:"
    echo "  1. Authenticate to Vault: vault login -method=oidc"
    echo "  2. Store your API key:    vault kv put secret/users/<entity-name>/anthropic api_key=sk-ant-..."
    echo "  3. Re-run this script:    bash .devcontainer/setup-claude-secrets.sh"
    echo ""
    echo "Your entity name is typically your GitHub username."
    exit 2
fi

# Get the entity name from Vault token lookup
# The entity_id is the UUID, we need to resolve it to the entity name
TOKEN_LOOKUP=$(vault token lookup -format=json 2>&1) || {
    log_error "Failed to look up Vault token: $TOKEN_LOOKUP"
    exit 1
}

ENTITY_ID=$(echo "$TOKEN_LOOKUP" | jq -r '.data.entity_id // empty')

if [[ -n "$ENTITY_ID" ]]; then
    # Try to get the entity name from the entity ID
    ENTITY_READ=$(vault read -format=json "identity/entity/id/${ENTITY_ID}" 2>&1) || {
        log_warn "Could not read entity details: $ENTITY_READ"
        ENTITY_NAME=""
    }
    if [[ -n "${ENTITY_READ:-}" ]]; then
        ENTITY_NAME=$(echo "$ENTITY_READ" | jq -r '.data.name // empty')
    fi
fi

# Fallback: extract from display_name (e.g., "github-username" -> "username")
if [[ -z "${ENTITY_NAME:-}" ]]; then
    DISPLAY_NAME=$(echo "$TOKEN_LOOKUP" | jq -r '.data.display_name // empty')
    if [[ -n "$DISPLAY_NAME" ]]; then
        ENTITY_NAME="${DISPLAY_NAME#github-}"
        log_info "Using entity name from display_name: $ENTITY_NAME"
    fi
fi

if [[ -z "${ENTITY_NAME:-}" ]]; then
    log_error "Could not determine Vault entity name."
    echo "Please ensure you have an entity configured in Vault."
    echo "If using GitHub auth, your entity name is typically your GitHub username."
    exit 1
fi

log_info "Checking for Anthropic API key for entity: $ENTITY_NAME"

# Try to fetch the API key from Vault
SECRET_PATH="secret/users/${ENTITY_NAME}/anthropic"
VAULT_OUTPUT=$(vault kv get -format=json "$SECRET_PATH" 2>&1) || {
    log_warn "Could not read secret from ${SECRET_PATH}"
    echo "Error: $VAULT_OUTPUT"
    echo ""
    echo "To store your Anthropic API key in Vault:"
    echo "  vault kv put ${SECRET_PATH} api_key=sk-ant-..."
    echo ""
    echo "Then re-run this script or start a new Claude Code session."
    exit 3
}

API_KEY=$(echo "$VAULT_OUTPUT" | jq -r '.data.data.api_key // empty')

if [[ -z "$API_KEY" ]]; then
    log_warn "Secret exists at ${SECRET_PATH} but 'api_key' field is empty or missing"
    echo ""
    echo "Expected secret format:"
    echo "  vault kv put ${SECRET_PATH} api_key=sk-ant-..."
    echo ""
    exit 3
fi

log_info "Found Anthropic API key in Vault"

# Set the ANTHROPIC_API_KEY environment variable for the current session
# and add it to .bashrc for future sessions
BASHRC="${HOME}/.bashrc"

# Use a unique delimiter for sed that won't appear in API keys
# API keys are base64-ish, so we use ASCII control character as delimiter
update_bashrc() {
    local key="$1"
    local bashrc="$2"

    # Write to a temp file and move atomically to avoid corruption
    local temp_file
    temp_file=$(mktemp)
    # Ensure temp file is cleaned up on exit or error
    trap 'rm -f "$temp_file"' RETURN

    if grep -q "^export ANTHROPIC_API_KEY=" "$bashrc" 2>/dev/null; then
        # Remove old entry and add new one
        grep -v "^export ANTHROPIC_API_KEY=" "$bashrc" > "$temp_file"
        echo "export ANTHROPIC_API_KEY='${key}'" >> "$temp_file"
        mv "$temp_file" "$bashrc"
        log_info "Updated ANTHROPIC_API_KEY in ~/.bashrc"
    elif grep -q "# Anthropic API key for Claude Code" "$bashrc" 2>/dev/null; then
        # Comment exists but export line was removed somehow - add it back
        echo "export ANTHROPIC_API_KEY='${key}'" >> "$bashrc"
        log_info "Re-added ANTHROPIC_API_KEY to ~/.bashrc"
    else
        # First time setup
        {
            echo ""
            echo "# Anthropic API key for Claude Code (from Vault)"
            echo "export ANTHROPIC_API_KEY='${key}'"
        } >> "$bashrc"
        log_info "Added ANTHROPIC_API_KEY to ~/.bashrc"
    fi
}

update_bashrc "$API_KEY" "$BASHRC"

# Export for current session
export ANTHROPIC_API_KEY="$API_KEY"

log_info "Claude Code API key configured successfully"
echo ""
echo "The ANTHROPIC_API_KEY environment variable has been set."
echo "Claude Code will use this key for API calls."
