#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Script to migrate secrets from 1Password to HashiCorp Vault

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

check_prerequisites() {
    log_step "Checking prerequisites..."

    local missing_tools=()

    if ! command -v vault &> /dev/null; then
        missing_tools+=("vault (HashiCorp Vault CLI)")
    fi

    if ! command -v op &> /dev/null; then
        missing_tools+=("op (1Password CLI)")
    fi

    if ! command -v ansible-vault &> /dev/null; then
        missing_tools+=("ansible-vault (Ansible)")
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools:"
        printf '%s\n' "${missing_tools[@]}"
        exit 1
    fi

    log_info "✓ All required tools found"
}

check_vault_auth() {
    log_step "Checking Vault authentication..."

    if [ -z "${VAULT_ADDR:-}" ]; then
        export VAULT_ADDR=https://vault.fzymgc.house
        log_info "Set VAULT_ADDR=$VAULT_ADDR"
    fi

    if ! vault token lookup &> /dev/null; then
        log_warn "Not authenticated to Vault"
        log_info "Running 'vault login'..."
        vault login
    else
        log_info "✓ Vault authentication valid"
    fi
}

extract_secrets() {
    log_step "Extracting secrets from current sources..."

    # Extract from .envrc (if it still has secrets - may already be migrated)
    # Temporarily disable strict error handling to allow missing vars
    set +u
    if [ -f .envrc ]; then
        # Safely source .envrc, ignoring errors
        set +e
        source .envrc 2>/dev/null
        set -e

        TPI_ALPHA_BMC="${TPI_ALPHA_BMC_ROOT_PW:-}"
        TPI_BETA_BMC="${TPI_BETA_BMC_ROOT_PW:-}"

        if [ -n "$TPI_ALPHA_BMC" ]; then
            log_info "✓ Found TPI Alpha BMC password in .envrc"
        else
            log_warn "TPI Alpha BMC password not found in .envrc (may already be migrated)"
        fi

        if [ -n "$TPI_BETA_BMC" ]; then
            log_info "✓ Found TPI Beta BMC password in .envrc"
        else
            log_warn "TPI Beta BMC password not found in .envrc (may already be migrated)"
        fi
    else
        log_warn ".envrc not found"
    fi
    set -u

    # Extract from 1Password (only if op command is available)
    if command -v op &> /dev/null; then
        log_info "Extracting secrets from 1Password..."

        set +e
        CLOUDFLARE_TOKEN=$(op item get --vault fzymgc-house "cloudflare-api-token" --fields password --reveal 2>/dev/null)
        set -e

        if [ -n "$CLOUDFLARE_TOKEN" ]; then
            log_info "✓ Found Cloudflare API token in 1Password"
        else
            log_warn "Cloudflare API token not found in 1Password"
        fi
    else
        log_warn "1Password CLI not available, skipping 1Password extraction"
        CLOUDFLARE_TOKEN=""
    fi
}

create_vault_secrets() {
    log_step "Creating secrets in Vault..."

    local created=0
    local skipped=0

    # Create BMC secrets
    if [ -n "${TPI_ALPHA_BMC:-}" ]; then
        log_info "Creating secret/fzymgc-house/infrastructure/bmc/tpi-alpha..."
        vault kv put secret/fzymgc-house/infrastructure/bmc/tpi-alpha password="$TPI_ALPHA_BMC"
        ((created++))
    else
        log_warn "Skipping TPI Alpha BMC (no value)"
        ((skipped++))
    fi

    if [ -n "${TPI_BETA_BMC:-}" ]; then
        log_info "Creating secret/fzymgc-house/infrastructure/bmc/tpi-beta..."
        vault kv put secret/fzymgc-house/infrastructure/bmc/tpi-beta password="$TPI_BETA_BMC"
        ((created++))
    else
        log_warn "Skipping TPI Beta BMC (no value)"
        ((skipped++))
    fi

    # Create Cloudflare secret
    if [ -n "${CLOUDFLARE_TOKEN:-}" ]; then
        log_info "Creating secret/fzymgc-house/infrastructure/cloudflare/api-token..."
        vault kv put secret/fzymgc-house/infrastructure/cloudflare/api-token token="$CLOUDFLARE_TOKEN"
        ((created++))
    else
        log_warn "Skipping Cloudflare API token (no value)"
        ((skipped++))
    fi

    log_info "✓ Created $created secrets, skipped $skipped"
    echo ""
    log_warn "NOTE: Vault root token is NOT migrated to Vault (cannot store root token in Vault itself)"
    log_info "Developers must authenticate with their own Vault token that has the 'infrastructure-developer' policy"
}

create_vault_policy() {
    log_step "Creating infrastructure-developer Vault policy..."

    local policy_file="tf/vault/policy-infrastructure-developer.hcl"

    if [ ! -f "$policy_file" ]; then
        log_error "Policy file not found: $policy_file"
        exit 1
    fi

    log_info "Creating policy from $policy_file..."
    # Temporarily disable exit on error for policy creation
    set +e
    vault policy write infrastructure-developer "$policy_file"
    local result=$?
    set -e

    if [ $result -eq 0 ]; then
        log_info "✓ Created infrastructure-developer policy"
    else
        log_warn "Failed to create policy (may already exist or insufficient permissions)"
    fi

    echo ""
}

verify_secrets() {
    log_step "Verifying secrets in Vault..."

    echo ""
    echo "Secrets created:"
    set +e
    vault kv list secret/fzymgc-house/infrastructure/
    set -e
    echo ""

    # Test reading one secret
    set +e
    vault kv get secret/fzymgc-house/infrastructure/bmc/tpi-alpha &> /dev/null
    local result=$?
    set -e

    if [ $result -eq 0 ]; then
        log_info "✓ Successfully verified secret access"
    else
        log_error "Failed to read secrets from Vault"
        exit 1
    fi
}

handle_ansible_vault() {
    log_step "Handling ansible-vault encrypted files..."

    if [ -f ansible/roles/k3sup/vars/main.yml ]; then
        echo ""
        log_warn "Found ansible-vault encrypted file: ansible/roles/k3sup/vars/main.yml"
        echo ""
        echo "To decrypt and view contents, run:"
        echo "  cd ansible && ansible-vault view roles/k3sup/vars/main.yml"
        echo ""
        echo "After viewing, manually create secrets in Vault with:"
        echo "  vault kv put secret/fzymgc-house/infrastructure/k3sup/<name> <key>=<value>"
        echo ""
        read -p "Press Enter to continue..."
    fi
}

main() {
    echo ""
    log_info "=========================================="
    log_info "  Vault Secrets Migration Script"
    log_info "=========================================="
    echo ""

    # Change to repo root
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    cd "$REPO_ROOT"

    check_prerequisites
    check_vault_auth
    create_vault_policy
    extract_secrets
    create_vault_secrets
    verify_secrets
    handle_ansible_vault

    echo ""
    log_info "=========================================="
    log_info "  Migration Complete!"
    log_info "=========================================="
    echo ""
    echo "Summary:"
    echo "  - Vault policy: infrastructure-developer created"
    echo "  - Secrets migrated: Check output above for details"
    echo "  - Secrets skipped: Check warnings above"
    echo ""
    echo "Next steps:"
    echo "  1. If secrets were skipped, manually add them to Vault:"
    echo "     vault kv put secret/fzymgc-house/infrastructure/bmc/tpi-alpha password=\"...\""
    echo "  2. Review docs/vault-migration.md for details"
    echo "  3. Test with: cd ansible && ansible-playbook --check ..."
    echo "  4. Developers need tokens with infrastructure-developer policy"
    echo ""
}

main "$@"
