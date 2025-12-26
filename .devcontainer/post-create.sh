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

# Configure git with container-appropriate settings
# Host ~/.gitconfig is NOT mounted (paths like credential helpers don't translate)
# Instead, we configure everything fresh with container-compatible values
log_info "Configuring git..."

setup_git_config() {
    # User identity - from environment variables passed from host
    # Set GIT_AUTHOR_NAME and GIT_AUTHOR_EMAIL on host to auto-configure
    local user_name="${GIT_AUTHOR_NAME:-}"
    local user_email="${GIT_AUTHOR_EMAIL:-}"

    if [[ -n "$user_name" && -n "$user_email" ]]; then
        git config --global user.name "$user_name"
        git config --global user.email "$user_email"
        log_info "✓ Git author: $user_name <$user_email>"
    else
        log_warn "Git author not configured"
        echo "    Set on host before container start:"
        echo "      export GIT_AUTHOR_NAME='Your Name'"
        echo "      export GIT_AUTHOR_EMAIL='your@email.com'"
        echo "    Or configure manually: git config --global user.name 'Your Name'"
    fi

    # Core settings
    git config --global init.defaultBranch main
    git config --global core.autocrlf input
    git config --global core.whitespace trailing-space,space-before-tab
    git config --global core.precomposeunicode true
    git config --global apply.whitespace nowarn

    # Delta pager (installed in Dockerfile)
    if command -v delta &> /dev/null; then
        git config --global core.pager delta
        git config --global interactive.diffFilter "delta --color-only"
        git config --global merge.conflictStyle diff3
        git config --global diff.colorMoved default
        # Delta options
        git config --global delta.navigate true
        git config --global delta.light false
        git config --global delta.line-numbers true
        git config --global delta.syntax-theme Dracula
        git config --global delta.hyperlinks true
        log_info "✓ Delta configured as git pager"
    fi

    # Branch and push behavior
    git config --global branch.autosetupmerge true
    git config --global branch.autosetuprebase always
    git config --global pull.rebase true
    git config --global fetch.prune true
    git config --global push.default simple
    git config --global push.autosetupremote true
    git config --global submodule.fetchjobs 4

    # Helpful defaults
    git config --global help.autocorrect 1
    git config --global log.decorate true
    git config --global status.submodulesummary true
    git config --global grep.extendRegexp true
    git config --global grep.lineNumber true

    # Color settings
    git config --global color.ui true
    git config --global color.diff auto
    git config --global color.status auto
    git config --global color.branch auto
    git config --global color.branch.current "yellow reverse"
    git config --global color.branch.local yellow
    git config --global color.branch.remote green
    git config --global color.diff.meta "yellow bold"
    git config --global color.diff.frag "magenta bold"
    git config --global color.diff.old "red bold"
    git config --global color.diff.new "green bold"
    git config --global color.status.added yellow
    git config --global color.status.changed green
    git config --global color.status.untracked cyan

    # Useful aliases
    git config --global alias.br branch
    git config --global alias.ci commit
    git config --global alias.co checkout
    git config --global alias.st "status -sb"
    git config --global alias.fa "fetch --all -p --tags"
    git config --global alias.please "push --force-with-lease"
    git config --global alias.commend "commit --amend --no-edit"
    git config --global alias.ls "log --pretty=format:'%C(yellow)%h%Cred%d %Creset%s%Cblue [%cn]' --decorate"
    git config --global alias.ll "log --pretty=format:'%C(yellow)%h%Cred%d %Creset%s%Cblue [%cn]' --decorate --numstat"
    git config --global alias.lt "log --tags --decorate --simplify-by-decoration --oneline"
    git config --global alias.unpushed "log @{u}.."
    git config --global alias.roots "log --all --oneline --decorate --max-parents=0"
    git config --global alias.changed "show --pretty=format: --name-only"
    git config --global alias.whatadded "log --diff-filter=A"
    log_info "✓ Git aliases configured"

    # Credential helper using GitHub CLI (if authenticated)
    if command -v gh &> /dev/null; then
        gh_err=""
        if gh_err=$(gh auth setup-git 2>&1); then
            log_info "✓ GitHub CLI configured as credential helper"
        else
            log_warn "Failed to configure gh as credential helper: $gh_err"
            echo "    Run 'gh auth login' then 'gh auth setup-git' after login-setup.sh"
        fi
    fi
}

setup_git_config

# Initialize git-lfs (installed in Dockerfile)
if command -v git-lfs &> /dev/null; then
    log_info "Initializing git-lfs..."
    if git lfs install --skip-repo &> /dev/null; then
        log_info "✓ git-lfs initialized"
    else
        log_warn "Failed to initialize git-lfs"
    fi
fi

# Disable GPG commit signing for this repo (container lacks access to signing keys)
log_info "Disabling GPG commit signing for this repository..."
if git config --local commit.gpgsign false 2>/dev/null; then
    log_info "✓ GPG commit signing disabled (local to repo)"
else
    log_warn "Failed to disable GPG commit signing"
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

# Install CLI tools via Homebrew (homebrew feature installed via devcontainer.json)
log_info "Installing CLI tools via Homebrew..."
if command -v brew &> /dev/null; then
    # Tools to install:
    # - bat: cat clone with syntax highlighting
    # - bottom: system monitor (btm command)
    # - gping: ping with graph visualization
    # - procs: modern ps replacement
    # - broot: file navigator
    # - tokei: code statistics
    # - xh: modern HTTP client (curl/httpie alternative)
    BREW_TOOLS="bat bottom gping procs broot tokei xh"
    for tool in $BREW_TOOLS; do
        if brew list "$tool" &> /dev/null; then
            log_info "✓ $tool already installed"
        else
            if brew install "$tool" &> /dev/null; then
                log_info "✓ $tool installed"
            else
                log_warn "Failed to install $tool"
            fi
        fi
    done
else
    log_warn "Homebrew not available, skipping CLI tool installation"
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
echo "  - git-lfs: $(git-lfs version 2>/dev/null || echo 'not available')"
echo "  - delta: $(delta --version 2>/dev/null || echo 'not available')"
echo "  - bat: $(bat --version 2>/dev/null | head -1 || echo 'not available')"
echo "  - btm: $(btm --version 2>/dev/null || echo 'not available')"
echo "  - gping: $(gping --version 2>/dev/null || echo 'not available')"
echo "  - procs: $(procs --version 2>/dev/null || echo 'not available')"
echo "  - broot: $(broot --version 2>/dev/null || echo 'not available')"
echo "  - tokei: $(tokei --version 2>/dev/null || echo 'not available')"
echo "  - xh: $(xh --version 2>/dev/null || echo 'not available')"
echo ""
echo "First-time setup:"
echo "  bash .devcontainer/login-setup.sh    # Interactive login for all services"
echo ""
echo "Useful commands:"
echo "  - Activate Python venv: source .venv/bin/activate"
echo "  - kubectl (alias 'k'):  k get nodes"
echo "  - Terraform (alias):    tf plan"
echo ""
