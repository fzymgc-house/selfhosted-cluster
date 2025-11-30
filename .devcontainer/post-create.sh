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

# Vault authentication setup
if command -v vault &> /dev/null; then
    log_info "Setting up Vault authentication..."
    export VAULT_ADDR="${VAULT_ADDR:-https://vault.fzymgc.house}"

    # Check if already authenticated
    if vault token lookup &> /dev/null; then
        log_info "✓ Already authenticated to Vault"
    else
        log_warn "Not authenticated to Vault"
        echo ""
        echo "Please authenticate to Vault to access infrastructure secrets:"
        echo "  vault login -method=github"
        echo ""
        echo "Then create an orphan token with infrastructure access:"
        echo "  vault token create -policy=infrastructure-developer -orphan"
        echo ""
        echo "Use the generated token for Terraform/Ansible operations."
        echo ""
    fi
fi

# GitHub CLI authentication
if command -v gh &> /dev/null; then
    log_info "Checking GitHub CLI authentication..."
    if gh auth status &> /dev/null; then
        log_info "✓ Already authenticated to GitHub"
    else
        log_warn "Not authenticated to GitHub CLI"
        echo ""
        echo "Please authenticate to GitHub (use HTTPS for best compatibility):"
        echo "  gh auth login -p https -w"
        echo ""
    fi
fi

# Terraform Cloud authentication
if command -v terraform &> /dev/null; then
    log_info "Checking Terraform Cloud authentication..."
    if [[ -f "${HOME}/.terraform.d/credentials.tfrc.json" ]]; then
        log_info "✓ Terraform Cloud credentials found"
    else
        log_warn "Not authenticated to Terraform Cloud"
        echo ""
        echo "Please authenticate to Terraform Cloud:"
        echo "  terraform login"
        echo ""
    fi
fi

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

# Set up kubectl default context if available
if command -v kubectl &> /dev/null && [[ -f "${HOME}/.kube/config" ]]; then
    log_info "Checking kubectl configuration..."
    if kubectl config get-contexts fzymgc-house &> /dev/null; then
        kubectl config use-context fzymgc-house
        log_info "✓ kubectl default context set to fzymgc-house"
    else
        log_warn "fzymgc-house context not found in kubeconfig"
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

# Install Claude Code CLI using native binary installer
log_info "Installing Claude Code CLI..."
# Ensure ~/.local/bin is in PATH (installer puts binary there)
if ! grep -q '\.local/bin' /home/vscode/.bashrc; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/vscode/.bashrc
fi
export PATH="$HOME/.local/bin:$PATH"

if command -v claude &> /dev/null; then
    log_info "✓ Claude Code CLI already installed: $(claude --version 2>/dev/null || echo 'unknown version')"
else
    # Use native binary installer (recommended by Anthropic)
    # Download first, then execute for better security practice
    INSTALL_SCRIPT="/tmp/claude-install.sh"
    if curl -fsSL https://claude.ai/install.sh -o "$INSTALL_SCRIPT"; then
        if bash "$INSTALL_SCRIPT"; then
            log_info "✓ Claude Code CLI installed successfully"
        else
            log_warn "Failed to install Claude Code CLI"
        fi
        rm -f "$INSTALL_SCRIPT"
    else
        log_warn "Failed to download Claude Code CLI installer"
    fi
fi

echo ""
log_info "=== Development environment setup complete! ==="
echo ""
echo "Available tools:"
echo "  - Claude Code: $(claude --version 2>/dev/null || echo 'not available')"
echo "  - Terraform: $(terraform version -json 2>/dev/null | jq -r .terraform_version || echo 'not available')"
echo "  - Ansible: $(ansible --version 2>/dev/null | head -1 || echo 'not available')"
echo "  - kubectl: $(kubectl version --client -o json 2>/dev/null | jq -r .clientVersion.gitVersion || echo 'not available')"
echo "  - helm: $(helm version --short 2>/dev/null || echo 'not available')"
echo "  - Python: $(python --version 2>&1)"
echo ""
echo "Useful commands:"
echo "  - Activate Python venv: source .venv/bin/activate"
echo "  - Vault login:          vault login -method=github"
echo "  - Vault infra token:    vault token create -policy=infrastructure-developer -orphan"
echo "  - GitHub login:         gh auth login -p https -w"
echo "  - Terraform login:      terraform login"
echo "  - kubectl (alias 'k'):  k get nodes"
echo "  - Terraform (alias):    tf plan"
echo ""
