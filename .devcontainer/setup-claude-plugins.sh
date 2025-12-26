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

# Check if Claude CLI is available (plugin setup is optional)
if ! command -v claude &> /dev/null; then
    log_warn "Claude CLI not found. Skipping plugin setup."
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
    if output=$(claude marketplace add "github:${repo}" --name "${name}" 2>&1); then
        log_info "✓ Added ${name}"
    else
        # Check if it's just an "already exists" case (use specific patterns to avoid masking errors)
        if [[ "$output" == *"already registered"* ]] || [[ "$output" == *"already exists"* ]]; then
            log_info "✓ Marketplace ${name} already configured"
        else
            log_warn "Failed to add ${name}: ${output}"
        fi
    fi
done

# Install plugins from workspace .claude/plugins.json if it exists
PLUGINS_FILE="${PWD}/.claude/plugins.json"
if [[ -f "$PLUGINS_FILE" ]]; then
    log_info "Installing plugins from ${PLUGINS_FILE}..."

    # Parse plugins array from JSON
    if command -v jq &> /dev/null; then
        if ! plugins=$(jq -r '.plugins[]?' "$PLUGINS_FILE" 2>&1); then
            log_warn "Failed to parse ${PLUGINS_FILE}: ${plugins}"
            log_info "Skipping plugin installation due to parse error"
        elif [[ -z "$plugins" ]]; then
            log_info "No plugins defined in ${PLUGINS_FILE}"
        else
            # Use while read to handle plugin names with spaces correctly
            while IFS= read -r plugin; do
                if [[ -n "$plugin" ]]; then
                    log_info "Installing plugin: ${plugin}"
                    if output=$(claude plugin install "${plugin}" 2>&1); then
                        log_info "✓ Installed ${plugin}"
                    else
                        # Check if it's just an "already installed" case (use specific pattern)
                        if [[ "$output" == *"already installed"* ]]; then
                            log_info "✓ Plugin ${plugin} already installed"
                        else
                            log_warn "Failed to install ${plugin}: ${output}"
                        fi
                    fi
                fi
            done <<< "$plugins"
        fi
    else
        log_warn "jq not found, cannot parse plugins.json"
    fi
else
    log_warn "No .claude/plugins.json found in workspace"
fi

log_info "Claude Code plugin setup complete"
