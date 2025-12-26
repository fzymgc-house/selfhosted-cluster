#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# shellcheck shell=bash
#
# Setup Python virtual environment for Ansible automation using uv
# Usage: ./setup-venv.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
VENV_DIR=".venv"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

main() {
    log_info "Setting up Python virtual environment for Ansible..."

    # Check for uv
    if ! command -v uv &> /dev/null; then
        log_error "uv not found. Please install uv: https://docs.astral.sh/uv/"
        exit 1
    fi
    log_info "Using uv $(uv --version | awk '{print $2}')"

    # Install Python packages using uv sync (creates venv if needed)
    # Note: In devcontainer, .venv is a Docker volume (Linux-native, persists across rebuilds)
    if [[ ! -f "pyproject.toml" ]]; then
        log_error "pyproject.toml not found"
        exit 1
    fi
    log_info "Installing Python packages from pyproject.toml (including dev dependencies)..."
    if ! uv sync --extra dev; then
        log_error "Failed to install Python packages. Check pyproject.toml and uv.lock are valid."
        exit 1
    fi

    # Activate for ansible-galaxy (needs VIRTUAL_ENV set)
    log_info "Activating virtual environment..."
    if [[ ! -f "${VENV_DIR}/bin/activate" ]]; then
        log_error "Virtual environment not found at ${VENV_DIR}/bin/activate"
        exit 1
    fi
    # shellcheck disable=SC1091
    source "${VENV_DIR}/bin/activate"

    # Install Ansible Galaxy collections
    if [[ -f "ansible/requirements.yml" ]]; then
        log_info "Installing Ansible Galaxy collections..."
        if ! ansible-galaxy collection install -r ansible/requirements.yml; then
            log_warn "Failed to install some Ansible collections (check network/permissions)"
        fi
    else
        log_warn "ansible/requirements.yml not found, skipping collections"
    fi

    # Verify installation
    log_info "Verifying installation..."
    echo ""
    echo "Python: $("${VENV_DIR}/bin/python" --version)"
    echo "Ansible: $(python -c 'import ansible; print(ansible.__version__)' 2>/dev/null || echo 'not installed')"
    echo ""

    log_info "Setup complete!"
    echo ""
    echo "To activate the virtual environment, run:"
    echo "  source ${VENV_DIR}/bin/activate"
    echo ""
    echo "Installed Ansible collections:"
    ansible-galaxy collection list 2>&1 | grep -E "kubernetes.core|community.general|community.hashi_vault" || echo "  (run 'ansible-galaxy collection list' to see installed collections)"
}

main "$@"
