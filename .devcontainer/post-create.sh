#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Post-create script for devcontainer setup

set -euo pipefail

echo "=== Setting up development environment ==="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Run the existing setup script
log_info "Running Python virtual environment setup..."
if [[ -f "setup-venv.sh" ]]; then
    bash setup-venv.sh
else
    log_warn "setup-venv.sh not found, skipping Python setup"
fi

# Configure git if not already configured
if [[ -z "$(git config --global user.name 2>/dev/null)" ]]; then
    log_info "Configuring git..."
    git config --global init.defaultBranch main
    git config --global pull.rebase true
    git config --global fetch.prune true
    echo "Please configure git user.name and user.email:"
    echo "  git config --global user.name 'Your Name'"
    echo "  git config --global user.email 'your.email@example.com'"
fi

# Set up kubectl context if available
if command -v kubectl &> /dev/null && [[ -f "${HOME}/.kube/config" ]]; then
    log_info "Checking kubectl configuration..."
    if kubectl config get-contexts fzymgc-house &> /dev/null; then
        kubectl config use-context fzymgc-house
        log_info "✓ kubectl context set to fzymgc-house"
    else
        log_warn "fzymgc-house context not found in kubeconfig"
    fi
fi

# Test 1Password CLI if socket is available
if [[ -S "${HOME}/.1password/agent.sock" ]]; then
    log_info "1Password agent socket detected"
    export OP_CONNECT_TOKEN="${OP_CONNECT_TOKEN:-}"
    if op account list &> /dev/null; then
        log_info "✓ 1Password CLI authenticated"
    else
        log_warn "1Password CLI not authenticated, some operations may fail"
    fi
fi

# Check Vault connectivity
if command -v curl &> /dev/null; then
    log_info "Checking Vault connectivity..."
    if curl -s --max-time 3 "${VAULT_ADDR:-https://vault.fzymgc.house}/v1/sys/health" > /dev/null 2>&1; then
        log_info "✓ Vault is reachable at ${VAULT_ADDR:-https://vault.fzymgc.house}"
    else
        log_warn "Vault not reachable, ensure VPN/network access"
    fi
fi

# Set up direnv if .envrc exists
if [[ -f ".envrc" ]]; then
    log_info "Setting up direnv..."
    direnv allow .
fi

echo ""
log_info "=== Development environment setup complete! ==="
echo ""
echo "Available tools:"
echo "  - Terraform: $(terraform version -json 2>/dev/null | jq -r .terraform_version || echo 'not available')"
echo "  - Ansible: $(ansible --version 2>/dev/null | head -1 || echo 'not available')"
echo "  - kubectl: $(kubectl version --client -o json 2>/dev/null | jq -r .clientVersion.gitVersion || echo 'not available')"
echo "  - helm: $(helm version --short 2>/dev/null || echo 'not available')"
echo "  - Python: $(python --version 2>&1)"
echo ""
echo "Useful commands:"
echo "  - Activate Python venv: source .venv/bin/activate"
echo "  - kubectl (cluster):    kubectl --context fzymgc-house get nodes"
echo "  - Terraform:            cd tf/authentik && terraform plan"
echo ""
