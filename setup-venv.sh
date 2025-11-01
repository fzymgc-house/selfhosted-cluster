#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# shellcheck shell=bash
#
# Setup Python virtual environment for Ansible automation
# Usage: ./setup-venv.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
VENV_DIR=".venv"
PYTHON_VERSION_FILE=".python-version"
REQUIRED_PYTHON_VERSION="3.13"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_python_version() {
    local python_cmd="$1"
    local version
    version=$($python_cmd --version 2>&1 | awk '{print $2}')
    local major_minor
    major_minor=$(echo "$version" | cut -d. -f1,2)

    if [[ $(echo "$major_minor >= $REQUIRED_PYTHON_VERSION" | bc -l) -eq 1 ]]; then
        echo "$version"
        return 0
    else
        return 1
    fi
}

find_python() {
    # Check for python3 command first
    if command -v python3 &> /dev/null; then
        if check_python_version python3 &> /dev/null; then
            echo "python3"
            return 0
        fi
    fi

    # Check for python command
    if command -v python &> /dev/null; then
        if check_python_version python &> /dev/null; then
            echo "python"
            return 0
        fi
    fi

    # Try version-specific commands
    for ver in 3.13 3.12 3.11; do
        if command -v "python${ver}" &> /dev/null; then
            if check_python_version "python${ver}" &> /dev/null; then
                echo "python${ver}"
                return 0
            fi
        fi
    done

    return 1
}

main() {
    log_info "Setting up Python virtual environment for Ansible..."

    # Find suitable Python
    log_info "Checking for Python ${REQUIRED_PYTHON_VERSION}+..."
    if ! PYTHON_CMD=$(find_python); then
        log_error "Python ${REQUIRED_PYTHON_VERSION}+ not found."
        log_error "Please install Python ${REQUIRED_PYTHON_VERSION} or newer."
        exit 1
    fi

    PYTHON_VERSION=$(check_python_version "$PYTHON_CMD")
    log_info "Found Python ${PYTHON_VERSION} at $(command -v "$PYTHON_CMD")"

    # Create virtual environment if it doesn't exist
    if [[ ! -d "$VENV_DIR" ]]; then
        log_info "Creating virtual environment in ${VENV_DIR}..."
        "$PYTHON_CMD" -m venv "$VENV_DIR"
    else
        log_info "Virtual environment already exists at ${VENV_DIR}"
    fi

    # Activate virtual environment
    log_info "Activating virtual environment..."
    # shellcheck disable=SC1091
    source "${VENV_DIR}/bin/activate"

    # Upgrade pip, setuptools, and wheel
    log_info "Upgrading pip, setuptools, and wheel..."
    pip install --upgrade pip setuptools wheel

    # Install Python requirements
    if [[ -f "requirements.txt" ]]; then
        log_info "Installing Python packages from requirements.txt..."
        pip install -r requirements.txt
    else
        log_warn "requirements.txt not found, skipping Python packages"
    fi

    # Install Ansible Galaxy collections
    if [[ -f "ansible/requirements-ansible.yml" ]]; then
        log_info "Installing Ansible Galaxy collections..."
        ansible-galaxy collection install -r ansible/requirements-ansible.yml
    else
        log_warn "ansible/requirements-ansible.yml not found, skipping collections"
    fi

    # Verify installation
    log_info "Verifying installation..."
    echo ""
    ansible --version
    echo ""

    log_info "✓ Setup complete!"
    echo ""
    echo "To activate the virtual environment, run:"
    echo "  source ${VENV_DIR}/bin/activate"
    echo ""
    echo "To deactivate, run:"
    echo "  deactivate"
    echo ""
    echo "Installed Ansible collections:"
    ansible-galaxy collection list | grep -E "kubernetes.core|community.general|community.hashi_vault" || true
}

main "$@"
