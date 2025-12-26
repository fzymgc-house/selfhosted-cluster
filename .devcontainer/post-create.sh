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

# Fix ownership of Docker volumes (created as root by default)
# These are mounted as named volumes and need proper vscode user ownership
# Note: PWD is the workspace directory, set by devcontainer before running postCreateCommand
log_info "Fixing Docker volume permissions..."
for dir in "/home/vscode/.cache" "${PWD}/.venv" "/tmp"; do
    if [[ -d "$dir" ]]; then
        chown_err=""
        if ! chown_err=$(sudo chown -R "$(id -u):$(id -g)" "$dir" 2>&1); then
            if [[ -n "$chown_err" ]]; then
                log_warn "Failed to fix permissions on $dir: $chown_err"
            else
                log_warn "Failed to fix permissions on $dir (no error details)"
            fi
        fi
    fi
done

# Vault authentication setup
if command -v vault &> /dev/null; then
    log_info "Setting up Vault authentication..."
    export VAULT_ADDR="${VAULT_ADDR:-https://vault.fzymgc.house}"

    # Check if already authenticated
    if vault token lookup &> /dev/null; then
        log_info "✓ Already authenticated to Vault"
    else
        log_warn "Not authenticated to Vault (run login-setup.sh to configure)"
    fi
fi

# GitHub CLI authentication
if command -v gh &> /dev/null; then
    log_info "Checking GitHub CLI authentication..."
    if gh auth status &> /dev/null; then
        log_info "✓ Already authenticated to GitHub"
    else
        log_warn "Not authenticated to GitHub CLI (run login-setup.sh to configure)"
    fi
fi

# Terraform Cloud authentication
if command -v terraform &> /dev/null; then
    log_info "Checking Terraform Cloud authentication..."
    if [[ -f "${HOME}/.terraform.d/credentials.tfrc.json" ]]; then
        log_info "✓ Terraform Cloud credentials found"
    else
        log_warn "Not authenticated to Terraform Cloud (run login-setup.sh to configure)"
    fi
fi

# Run the existing setup script
log_info "Running Python virtual environment setup..."
if [[ -f "setup-venv.sh" ]]; then
    bash setup-venv.sh
else
    log_warn "setup-venv.sh not found, skipping Python setup"
fi

# Configure git defaults and verify author info
# Note: Run from /tmp to avoid git worktree path issues in container
# (worktree .git file references host path that doesn't exist inside container)
log_info "Configuring git..."

# Check if gitconfig is writable (may be read-only bind mount from host)
if [[ -w "${HOME}/.gitconfig" ]] || [[ ! -f "${HOME}/.gitconfig" ]]; then
    # Writable or doesn't exist yet - safe to set defaults
    git_config_err=""
    if ! git_config_err=$(cd /tmp && git config --global init.defaultBranch main && \
                          git config --global pull.rebase true && \
                          git config --global fetch.prune true 2>&1); then
        log_warn "Failed to configure git defaults: ${git_config_err:-unknown error}"
    fi
else
    log_info "\$HOME/.gitconfig is read-only (mounted from host), using existing settings"
fi

# Check if git author info is available (from mounted ~/.gitconfig or prior config)
# Note: git config exits 1 if key not set, other codes indicate real errors
if ! GIT_USER_NAME="$(cd /tmp && git config --global user.name 2>&1)"; then
    GIT_USER_NAME=""
fi
if ! GIT_USER_EMAIL="$(cd /tmp && git config --global user.email 2>&1)"; then
    GIT_USER_EMAIL=""
fi

if [[ -n "$GIT_USER_NAME" && -n "$GIT_USER_EMAIL" ]]; then
    log_info "✓ Git author: $GIT_USER_NAME <$GIT_USER_EMAIL>"
elif [[ ! -f "${HOME}/.gitconfig" ]]; then
    log_warn "\$HOME/.gitconfig not mounted (file may not exist on host)"
    echo "    Create on host: git config --global user.name 'Your Name'"
    echo "                    git config --global user.email 'your.email@example.com'"
    echo "    Or configure manually in container after rebuild"
elif [[ -z "$GIT_USER_NAME" && -z "$GIT_USER_EMAIL" ]]; then
    log_warn "Git author not configured in ~/.gitconfig"
    echo "    Configure on host:"
    echo "      git config --global user.name 'Your Name'"
    echo "      git config --global user.email 'your.email@example.com'"
else
    # Partial config - one is set, one is missing
    log_warn "Git author incomplete in ~/.gitconfig"
    [[ -z "$GIT_USER_NAME" ]] && echo "    Missing: git config --global user.name 'Your Name'"
    [[ -z "$GIT_USER_EMAIL" ]] && echo "    Missing: git config --global user.email 'your.email@example.com'"
fi

# Set up kubectl default context if available
# KUBECONFIG is set in devcontainer.json to ~/.kube/configs/fzymgc-house-admin.yml
if command -v kubectl &> /dev/null && [[ -f "${KUBECONFIG:-${HOME}/.kube/config}" ]]; then
    log_info "Checking kubectl configuration..."
    if kubectl config get-contexts fzymgc-house &> /dev/null; then
        kubectl_err=""
        if kubectl_err=$(kubectl config use-context fzymgc-house 2>&1); then
            log_info "✓ kubectl default context set to fzymgc-house"
        else
            if [[ -n "$kubectl_err" ]]; then
                log_warn "Failed to switch to fzymgc-house context: $kubectl_err"
            else
                log_warn "Failed to switch to fzymgc-house context (no error details)"
            fi
        fi
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
    direnv_err=""
    if ! direnv_err=$(direnv allow . 2>&1); then
        log_warn "Failed to enable direnv: $direnv_err"
        log_warn "You may need to run 'direnv allow' manually"
    fi
fi

# Install ast-grep for Serena MCP semantic code operations
log_info "Installing ast-grep..."
if command -v ast-grep &> /dev/null; then
    log_info "✓ ast-grep already installed: $(ast-grep --version 2>/dev/null || echo 'unknown version')"
else
    if npm install -g @ast-grep/cli; then
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
    set +e  # Temporarily allow non-zero exit
    bash .devcontainer/setup-claude-secrets.sh
    secrets_exit_code=$?
    set -e
    case $secrets_exit_code in
        0)
            log_info "✓ Claude Code API key configured from Vault"
            ;;
        2)
            log_info "Vault auth skipped - configure later with 'vault login'"
            ;;
        3)
            log_warn "API key not found in Vault - store it and re-run script"
            ;;
        *)
            log_warn "Unexpected error setting up Claude secrets (exit $secrets_exit_code)"
            ;;
    esac
else
    log_warn "setup-claude-secrets.sh not found, skipping Anthropic API key setup"
fi

# Verify Claude Code is available (installed by devcontainer feature)
# Note: Marketplaces and plugins are configured declaratively in .claude/settings.json
# (extraKnownMarketplaces and enabledPlugins) - no runtime setup needed
if command -v claude &> /dev/null; then
    log_info "✓ Claude Code CLI available: $(claude --version 2>/dev/null || echo 'unknown version')"
    log_info "  Plugins configured via .claude/settings.json (applied on folder trust)"
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
echo "First-time setup:"
echo "  bash .devcontainer/login-setup.sh    # Interactive login for all services"
echo ""
echo "Useful commands:"
echo "  - Activate Python venv: source .venv/bin/activate"
echo "  - kubectl (alias 'k'):  k get nodes"
echo "  - Terraform (alias):    tf plan"
echo ""
