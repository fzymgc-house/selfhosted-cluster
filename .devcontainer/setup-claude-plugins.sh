#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Set up Claude Code marketplaces and plugins for devcontainer
#
# This script adds required marketplaces and installs plugins defined in
# the workspace's .claude/plugins.json file.

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
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Claude CLI is available
if ! command -v claude &> /dev/null; then
    log_error "Claude CLI not found. Skipping plugin setup."
    exit 0
fi

log_info "Setting up Claude Code marketplaces and plugins..."

# Required marketplaces for this project
# Format: "name|github-repo"
MARKETPLACES=(
    "superpowers-marketplace|obra/superpowers-marketplace"
    "claude-code-plugins|anthropics/claude-code"
    "claude-plugins-official|anthropics/claude-plugins-official"
    "fzymgc-house-skills|fzymgc-house/fzymgc-house-skills"
)

# Add marketplaces
for marketplace in "${MARKETPLACES[@]}"; do
    name="${marketplace%%|*}"
    repo="${marketplace##*|}"

    log_info "Adding marketplace: ${name} (${repo})"
    if claude marketplace add "github:${repo}" --name "${name}" 2>/dev/null; then
        log_info "✓ Added ${name}"
    else
        # Marketplace might already exist
        log_warn "Marketplace ${name} may already exist or failed to add"
    fi
done

# Install plugins from workspace .claude/plugins.json if it exists
PLUGINS_FILE="${PWD}/.claude/plugins.json"
if [[ -f "$PLUGINS_FILE" ]]; then
    log_info "Installing plugins from ${PLUGINS_FILE}..."

    # Parse plugins array from JSON
    if command -v jq &> /dev/null; then
        plugins=$(jq -r '.plugins[]?' "$PLUGINS_FILE" 2>/dev/null || echo "")

        for plugin in $plugins; do
            if [[ -n "$plugin" ]]; then
                log_info "Installing plugin: ${plugin}"
                if claude plugin install "${plugin}" 2>/dev/null; then
                    log_info "✓ Installed ${plugin}"
                else
                    log_warn "Failed to install ${plugin} (may already be installed)"
                fi
            fi
        done
    else
        log_warn "jq not found, cannot parse plugins.json"
    fi
else
    log_warn "No .claude/plugins.json found in workspace"
fi

log_info "Claude Code plugin setup complete"
