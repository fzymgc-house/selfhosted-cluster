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

# Install ast-grep for Serena MCP semantic code operations
log_info "Installing ast-grep..."
if command -v ast-grep &> /dev/null; then
    log_info "✓ ast-grep already installed: $(ast-grep --version 2>/dev/null || echo 'unknown version')"
else
    if npm install -g @ast-grep/cli 2>/dev/null; then
        log_info "✓ ast-grep installed successfully"
    else
        log_warn "Failed to install ast-grep (Serena MCP may have reduced functionality)"
    fi
fi

# Set up git safeguards to warn on --no-verify usage
log_info "Setting up git safeguards..."
setup_git_safeguards() {
    local bashrc="/home/vscode/.bashrc"
    local safeguard_marker="# Git safeguards for Claude Code"

    if ! grep -q "$safeguard_marker" "$bashrc" 2>/dev/null; then
        cat >> "$bashrc" << 'SAFEGUARDS'

# Git safeguards for Claude Code
# Warn when using --no-verify to prevent accidental pre-commit bypass
git() {
    local args=("$@")
    local has_no_verify=false

    for arg in "${args[@]}"; do
        if [[ "$arg" == "--no-verify" || "$arg" == "-n" ]]; then
            has_no_verify=true
            break
        fi
    done

    if $has_no_verify; then
        echo -e "\033[1;33m[WARNING]\033[0m You are using --no-verify which skips pre-commit hooks."
        echo "This may allow code that doesn't meet project standards to be committed."
        read -r -p "Continue anyway? [y/N] " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Commit aborted."
            return 1
        fi
    fi

    command git "${args[@]}"
}
SAFEGUARDS
        log_info "✓ Git safeguards added to ~/.bashrc"
    else
        log_info "✓ Git safeguards already configured"
    fi
}
setup_git_safeguards

# Set up Claude Code with Vault-sourced API key
log_info "Setting up Claude Code API key from Vault..."
if [[ -f ".devcontainer/setup-claude-secrets.sh" ]]; then
    bash .devcontainer/setup-claude-secrets.sh
else
    log_warn "setup-claude-secrets.sh not found, skipping Anthropic API key setup"
fi

# Verify Claude Code is available (installed by devcontainer feature)
if command -v claude &> /dev/null; then
    log_info "✓ Claude Code CLI available: $(claude --version 2>/dev/null || echo 'unknown version')"
else
    log_warn "Claude Code CLI not found (should be installed by devcontainer feature)"
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
echo "  - ast-grep: $(ast-grep --version 2>/dev/null || echo 'not available')"
echo "  - uv: $(uv --version 2>/dev/null || echo 'not available')"
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
