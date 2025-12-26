#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Create a Vault token for use in devcontainer
#
# Run this script on your HOST (not inside the devcontainer) to create
# a child token that can be used for container authentication.
#
# The token has:
#   - 8 hour TTL (enough for a work session)
#   - Inherits parent's identity entity (required for templated policies)
#   - claude-code policy (access to user secrets)
#
# Note: Child tokens inherit the parent's entity, which is required for
# the {{identity.entity.name}} templating in the claude-code policy.
# The token will be revoked if the parent OIDC token is revoked, but
# OIDC tokens typically last ~14 days which is plenty for dev sessions.
#
# Usage:
#   ./create-vault-token.sh
#   # Then paste the token in the devcontainer when prompted

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "${BLUE}[→]${NC} $1"; }

# Check if running inside a container (should NOT be)
if [[ -n "${REMOTE_CONTAINERS:-}" ]] || [[ -n "${DEVCONTAINER:-}" ]] || [[ -n "${CODESPACES:-}" ]]; then
    log_error "This script should be run on your HOST machine, not inside a container."
    echo ""
    echo "The Vault OIDC login requires a browser callback to localhost:8250,"
    echo "which doesn't work from inside containers."
    echo ""
    echo "Please run this script from a terminal on your host machine."
    exit 1
fi

# Vault configuration
export VAULT_ADDR="${VAULT_ADDR:-https://vault.fzymgc.house}"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          Create Vault Token for Devcontainer               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "This script creates a short-lived Vault token you can use"
echo "inside the devcontainer (where OIDC login doesn't work)."
echo ""

# Check Vault CLI
if ! command -v vault &> /dev/null; then
    log_error "Vault CLI not found. Install it first:"
    echo "  brew install vault  # macOS"
    echo "  sudo apt install vault  # Linux"
    exit 1
fi

# Check jq CLI
if ! command -v jq &> /dev/null; then
    log_error "jq not found. Install it first:"
    echo "  brew install jq  # macOS"
    echo "  sudo apt install jq  # Linux"
    exit 1
fi

# Check Vault authentication
if ! vault token lookup &> /dev/null; then
    log_step "Not authenticated to Vault. Starting OIDC login..."
    echo ""
    if ! vault login -method=oidc; then
        log_error "Vault OIDC login failed."
        exit 1
    fi
    echo ""
fi

log_info "Authenticated to Vault at ${VAULT_ADDR}"

# Get entity info for display
TOKEN_LOOKUP=$(vault token lookup -format=json 2>/dev/null)
ENTITY_ID=$(echo "$TOKEN_LOOKUP" | jq -r '.data.entity_id // empty')
DISPLAY_NAME=$(echo "$TOKEN_LOOKUP" | jq -r '.data.display_name // empty')

if [[ -n "$ENTITY_ID" ]]; then
    ENTITY_NAME=$(vault read -format=json "identity/entity/id/${ENTITY_ID}" 2>/dev/null | jq -r '.data.name // empty') || true
fi
if [[ -z "${ENTITY_NAME:-}" ]]; then
    ENTITY_NAME="${DISPLAY_NAME#github-}"
    ENTITY_NAME="${ENTITY_NAME#oidc-}"
fi

if [[ -z "${ENTITY_NAME:-}" ]]; then
    log_warn "Could not determine Vault entity name."
    echo "    The token will be created, but API key paths may not resolve correctly."
    echo "    Expected format: secret/users/<entity-name>/anthropic"
    echo ""
fi

log_info "Vault entity: ${ENTITY_NAME:-unknown}"

# Create child token with limited TTL (inherits parent's entity for templated policies)
log_step "Creating devcontainer token (8 hour TTL)..."

TOKEN_OUTPUT=$(vault token create \
    -ttl=8h \
    -display-name="devcontainer-${ENTITY_NAME:-user}" \
    -policy=claude-code \
    -format=json 2>&1) || {
    log_error "Failed to create token."
    echo ""
    echo "Error: $TOKEN_OUTPUT"
    echo ""
    echo "Make sure you have permission to create tokens."
    exit 1
}

TOKEN=$(echo "$TOKEN_OUTPUT" | jq -r '.auth.client_token')
TTL=$(echo "$TOKEN_OUTPUT" | jq -r '.auth.lease_duration')

echo ""
log_info "Token created successfully!"
echo ""

# Try to copy to clipboard if available (macOS pbcopy, Linux xclip/xsel)
COPIED_TO_CLIPBOARD=false
if command -v pbcopy &>/dev/null; then
    echo -n "$TOKEN" | pbcopy
    COPIED_TO_CLIPBOARD=true
elif command -v xclip &>/dev/null; then
    echo -n "$TOKEN" | xclip -selection clipboard
    COPIED_TO_CLIPBOARD=true
elif command -v xsel &>/dev/null; then
    echo -n "$TOKEN" | xsel --clipboard
    COPIED_TO_CLIPBOARD=true
fi

if $COPIED_TO_CLIPBOARD; then
    echo "────────────────────────────────────────────────────────────────"
    echo ""
    log_info "Token copied to clipboard!"
    echo ""
    echo "Token details:"
    echo "  - TTL: ${TTL} seconds (~8 hours)"
    echo "  - Policy: claude-code"
    echo "  - Entity: ${ENTITY_NAME:-unknown} (inherited from parent)"
    echo ""
else
    echo "────────────────────────────────────────────────────────────────"
    echo ""
    log_warn "Could not copy to clipboard. Token displayed below."
    echo -e "    ${YELLOW}(Clear terminal after copying if on shared screen)${NC}"
    echo ""
    echo "$TOKEN"
    echo ""
    echo "────────────────────────────────────────────────────────────────"
    echo ""
    echo "Token details:"
    echo "  - TTL: ${TTL} seconds (~8 hours)"
    echo "  - Policy: claude-code"
    echo "  - Entity: ${ENTITY_NAME:-unknown} (inherited from parent)"
    echo ""
fi

echo "In the devcontainer, run:"
echo "  bash .devcontainer/login-setup.sh"
echo ""
echo "When prompted for Vault login, paste the token."
echo ""
