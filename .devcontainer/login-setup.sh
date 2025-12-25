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

# Vault
if vault token lookup &>/dev/null; then
    log_info "Vault: Authenticated"
else
    log_warn "Vault: Not authenticated"
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

# Claude (check env var)
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    log_info "Claude Code: API key configured"
else
    log_warn "Claude Code: API key not configured"
    needs_claude=true
fi

echo ""

# If everything is set up, exit early
if ! $needs_vault && ! $needs_github && ! $needs_terraform && ! $needs_claude; then
    echo "All services authenticated! You're ready to develop."
    exit 0
fi

echo "────────────────────────────────────────────────────────────────"
echo ""

# Step 1: Vault (required for Claude secrets)
if $needs_vault; then
    log_step "Step 1: Vault Authentication"
    echo "    Vault stores secrets including the Claude Code API key."
    echo ""
    read -p "    Run 'vault login -method=oidc'? [Y/n] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        vault login -method=oidc || {
            log_warn "Vault login failed. You can retry later with: vault login -method=oidc"
        }
    fi
    echo ""
fi

# Step 2: Claude API key (after Vault is set up)
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
        SECRET_PATH="secret/users/${ENTITY_NAME}/anthropic"

        # Check if API key already exists
        if vault kv get -format=json "$SECRET_PATH" &>/dev/null; then
            log_info "Claude API key found in Vault at ${SECRET_PATH}"
            # Run the setup script to configure it
            if ! bash .devcontainer/setup-claude-secrets.sh; then
                log_warn "Failed to configure Claude API key (exit code: $?)"
            fi
        else
            log_step "Step 2: Claude Code API Key"
            echo "    Your Anthropic API key needs to be stored in Vault."
            echo "    Path: ${SECRET_PATH}"
            echo ""
            read -p "    Do you have an Anthropic API key to store? [y/N] " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo ""
                echo "    Enter your Anthropic API key (starts with sk-ant-):"
                read -rs ANTHROPIC_KEY
                echo ""
                if [[ -n "$ANTHROPIC_KEY" ]]; then
                    if vault kv put "$SECRET_PATH" api_key="$ANTHROPIC_KEY" &>/dev/null; then
                        log_info "API key stored in Vault"
                        # Configure it for the current session
                        if ! bash .devcontainer/setup-claude-secrets.sh; then
                            log_warn "Failed to configure Claude API key for session"
                        fi
                    else
                        log_warn "Failed to store API key. Check your Vault permissions."
                    fi
                fi
            else
                echo ""
                echo "    You can store your API key later with:"
                echo "      vault kv put ${SECRET_PATH} api_key=sk-ant-..."
                echo ""
            fi
        fi
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
