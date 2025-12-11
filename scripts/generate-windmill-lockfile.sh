#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Generate Windmill script lockfiles from requirements files.
#
# Usage:
#   ./scripts/generate-windmill-lockfile.sh <script.py>
#   ./scripts/generate-windmill-lockfile.sh windmill/f/terraform/notify_approval.py
#
# This script:
#   1. Reads #requirements: comments from the script OR adjacent requirements.txt
#   2. Creates a temporary venv and installs dependencies
#   3. Generates a .script.lock file with all transitive dependencies
#
# The lockfile format is:
#   # py: <python_version>
#   package1==version1
#   package2==version2
#   ...

set -euo pipefail

PYTHON_VERSION="${WINDMILL_PYTHON_VERSION:-3.11}"

usage() {
    echo "Usage: $0 <script.py> [--dry-run]"
    echo
    echo "Generate a Windmill .script.lock file for a Python script."
    echo
    echo "Options:"
    echo "  --dry-run    Print lockfile to stdout instead of writing to file"
    echo
    echo "Examples:"
    echo "  $0 windmill/f/terraform/notify_approval.py"
    echo "  $0 windmill/f/terraform/notify_approval.py --dry-run"
    exit 1
}

# Parse arguments
SCRIPT_PATH=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [[ -z "$SCRIPT_PATH" ]]; then
                SCRIPT_PATH="$1"
            else
                echo "Error: Unexpected argument: $1" >&2
                usage
            fi
            shift
            ;;
    esac
done

if [[ -z "$SCRIPT_PATH" ]]; then
    echo "Error: Script path required" >&2
    usage
fi

if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "Error: Script not found: $SCRIPT_PATH" >&2
    exit 1
fi

# Get script directory and base name
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
SCRIPT_BASE="$(basename "$SCRIPT_PATH" .py)"
LOCKFILE_PATH="${SCRIPT_DIR}/${SCRIPT_BASE}.script.lock"

# Extract requirements from script or requirements.txt
get_requirements() {
    local script="$1"
    local script_dir
    script_dir="$(dirname "$script")"

    # First check for adjacent requirements.txt (Windmill's preferred source)
    if [[ -f "${script_dir}/requirements.txt" ]]; then
        # Read non-empty, non-comment lines
        grep -v '^#' "${script_dir}/requirements.txt" | grep -v '^\s*$' || true
        return
    fi

    # Fall back to parsing #requirements: comments from script
    # Format: #requirements:
    #         #package1
    #         #package2>=1.0
    local in_requirements=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^#requirements: ]]; then
            in_requirements=true
            continue
        fi
        if $in_requirements; then
            if [[ "$line" =~ ^#([a-zA-Z0-9_-]+.*) ]]; then
                echo "${BASH_REMATCH[1]}"
            elif [[ ! "$line" =~ ^# ]]; then
                # End of requirements block
                break
            fi
        fi
    done < "$script"
}

# Get requirements
REQUIREMENTS=$(get_requirements "$SCRIPT_PATH")

if [[ -z "$REQUIREMENTS" ]]; then
    echo "No requirements found for $SCRIPT_PATH" >&2
    echo "Creating lockfile with no dependencies..."
    LOCKFILE_CONTENT="# py: ${PYTHON_VERSION}"
else
    echo "Found requirements:"
    echo "$REQUIREMENTS" | sed 's/^/  /'
    echo

    # Create temporary directory for venv
    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT

    echo "Creating temporary venv..."
    python3 -m venv "$TEMP_DIR/venv"

    # Install requirements
    echo "Installing dependencies..."
    # shellcheck disable=SC1091
    source "$TEMP_DIR/venv/bin/activate"

    # Write requirements to temp file
    echo "$REQUIREMENTS" > "$TEMP_DIR/requirements.txt"

    # Install quietly, ignoring pip's cache warnings
    pip install --quiet -r "$TEMP_DIR/requirements.txt" 2>&1 | grep -v "WARNING:" || true

    # Generate lockfile content
    echo "Resolving all transitive dependencies..."
    FROZEN_DEPS=$(pip freeze 2>&1 | grep -v "WARNING:" | sort)

    deactivate

    LOCKFILE_CONTENT="# py: ${PYTHON_VERSION}
${FROZEN_DEPS}"
fi

# Output or write lockfile
if $DRY_RUN; then
    echo
    echo "=== Lockfile content ==="
    echo "$LOCKFILE_CONTENT"
else
    echo "$LOCKFILE_CONTENT" > "$LOCKFILE_PATH"
    echo
    echo "Generated: $LOCKFILE_PATH"
    echo
    echo "Contents:"
    cat "$LOCKFILE_PATH" | sed 's/^/  /'
fi
