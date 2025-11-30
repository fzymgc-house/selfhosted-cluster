#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Helper script for Vault operations in this repository

set -euo pipefail

# Configuration
VAULT_ADDR="${VAULT_ADDR:-https://vault.fzymgc.house}"
VAULT_NAMESPACE="secret/fzymgc-house/infrastructure"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_vault() {
    if ! command -v vault &> /dev/null; then
        log_error "vault CLI not found. Install from https://www.vaultproject.io/downloads"
        exit 1
    fi

    export VAULT_ADDR

    if ! vault token lookup &> /dev/null; then
        log_error "Not authenticated to Vault. Run: vault login"
        exit 1
    fi
}

cmd_get() {
    local path="${1:-}"
    if [ -z "$path" ]; then
        log_error "Usage: $0 get <path> [field]"
        exit 1
    fi

    local field="${2:-}"
    local full_path="$VAULT_NAMESPACE/$path"

    if [ -n "$field" ]; then
        vault kv get -field="$field" "$full_path"
    else
        vault kv get "$full_path"
    fi
}

cmd_put() {
    local path="${1:-}"
    shift || true

    if [ -z "$path" ] || [ $# -eq 0 ]; then
        log_error "Usage: $0 put <path> <key>=<value> [<key>=<value> ...]"
        exit 1
    fi

    local full_path="$VAULT_NAMESPACE/$path"
    vault kv put "$full_path" "$@"
}

cmd_list() {
    local path="${1:-}"
    local full_path="$VAULT_NAMESPACE/$path"
    vault kv list "$full_path"
}

cmd_delete() {
    local path="${1:-}"
    if [ -z "$path" ]; then
        log_error "Usage: $0 delete <path>"
        exit 1
    fi

    local full_path="$VAULT_NAMESPACE/$path"
    echo "Are you sure you want to delete $full_path? (yes/no)"
    read -r confirm
    if [ "$confirm" = "yes" ]; then
        vault kv delete "$full_path"
        log_info "Deleted $full_path"
    else
        log_info "Cancelled"
    fi
}

cmd_login() {
    export VAULT_ADDR
    vault login
}

cmd_status() {
    export VAULT_ADDR
    echo "VAULT_ADDR: $VAULT_ADDR"
    echo "VAULT_NAMESPACE: $VAULT_NAMESPACE"
    echo ""

    if vault token lookup &> /dev/null; then
        echo "Authentication: ✓ Valid"
        vault token lookup | grep -E "(accessor|display_name|policies|expire_time)"
    else
        echo "Authentication: ✗ Not authenticated"
    fi
}

show_usage() {
    cat << EOF
Usage: $0 <command> [args]

Vault helper for infrastructure secrets in $VAULT_NAMESPACE

Commands:
  login               Authenticate to Vault
  status              Show Vault connection and auth status
  get <path> [field]  Get a secret (optionally just one field)
  put <path> k=v ...  Create/update a secret
  list [path]         List secrets at path
  delete <path>       Delete a secret

Examples:
  $0 status
  $0 login
  $0 list
  $0 list bmc
  $0 get bmc/tpi-alpha
  $0 get bmc/tpi-alpha password
  $0 put bmc/tpi-alpha password="newpassword"
  $0 delete test/secret

Note: All paths are relative to $VAULT_NAMESPACE
EOF
}

main() {
    local command="${1:-}"

    case "$command" in
        login)
            cmd_login
            ;;
        status)
            cmd_status
            ;;
        get)
            check_vault
            shift
            cmd_get "$@"
            ;;
        put)
            check_vault
            shift
            cmd_put "$@"
            ;;
        list|ls)
            check_vault
            shift
            cmd_list "$@"
            ;;
        delete|rm)
            check_vault
            shift
            cmd_delete "$@"
            ;;
        help|--help|-h|"")
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
