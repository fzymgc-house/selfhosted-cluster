#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Helper script for using devcontainer from terminal (Warp, iTerm2, etc.)

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="selfhosted-cluster-dev"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

check_devcontainer_cli() {
    if ! command -v devcontainer &> /dev/null; then
        log_error "devcontainer CLI not found!"
        echo ""
        echo "Install it with:"
        echo "  npm install -g @devcontainers/cli"
        echo ""
        exit 1
    fi
}

show_usage() {
    cat << EOF
Usage: ./dev.sh <command> [options]

Commands:
  build       Build the devcontainer image
  rebuild     Rebuild the devcontainer from scratch (no cache)
  up          Start the devcontainer (if not running)
  shell       Open an interactive shell in the container
  exec        Execute a command in the container
  stop        Stop the devcontainer
  down        Stop and remove the devcontainer
  clean       Remove container and rebuild from scratch
  status      Show container status
  logs        Show container logs

Examples:
  ./dev.sh build                    # Build the container
  ./dev.sh shell                    # Open interactive shell
  ./dev.sh exec "terraform version" # Run command
  ./dev.sh exec "source .venv/bin/activate && ansible --version"

Environment:
  WORKSPACE_FOLDER   Override workspace folder (default: current directory)
EOF
}

cmd_build() {
    log_step "Building devcontainer image..."
    cd "$REPO_ROOT"
    devcontainer build --workspace-folder .
    log_info "✓ Build complete!"
}

cmd_rebuild() {
    log_step "Rebuilding devcontainer from scratch..."
    cd "$REPO_ROOT"
    devcontainer build --workspace-folder . --no-cache
    log_info "✓ Rebuild complete!"
}

cmd_up() {
    log_step "Starting devcontainer..."
    cd "$REPO_ROOT"
    devcontainer up --workspace-folder .
    log_info "✓ Container is running"
}

cmd_shell() {
    log_step "Opening interactive shell in devcontainer..."
    cd "$REPO_ROOT"

    # Ensure container is running
    devcontainer up --workspace-folder . > /dev/null 2>&1

    # Open interactive shell with nice prompt
    devcontainer exec --workspace-folder . bash -c '
        cd /workspace
        source .venv/bin/activate 2>/dev/null || true
        export PS1="\[\033[1;36m\][devcontainer]\[\033[0m\] \[\033[1;34m\]\w\[\033[0m\] \$ "
        bash --login
    '
}

cmd_exec() {
    if [[ $# -eq 0 ]]; then
        log_error "No command provided"
        echo "Usage: ./dev.sh exec \"<command>\""
        exit 1
    fi

    local cmd="$1"
    log_step "Executing command in devcontainer..."
    cd "$REPO_ROOT"

    # Ensure container is running
    devcontainer up --workspace-folder . > /dev/null 2>&1

    # Execute the command
    devcontainer exec --workspace-folder . bash -c "cd /workspace && $cmd"
}

cmd_stop() {
    log_step "Stopping devcontainer..."

    # Find and stop the container
    local container_id
    container_id=$(docker ps -q --filter "label=devcontainer.local_folder=$REPO_ROOT" | head -1)

    if [[ -n "$container_id" ]]; then
        docker stop "$container_id"
        log_info "✓ Container stopped"
    else
        log_warn "No running container found"
    fi
}

cmd_down() {
    log_step "Stopping and removing devcontainer..."
    cd "$REPO_ROOT"
    devcontainer down --workspace-folder .
    log_info "✓ Container removed"
}

cmd_clean() {
    log_step "Cleaning up and rebuilding..."
    cmd_down
    cmd_rebuild
    log_info "✓ Clean rebuild complete!"
}

cmd_status() {
    log_step "Checking devcontainer status..."

    local container_id
    container_id=$(docker ps -aq --filter "label=devcontainer.local_folder=$REPO_ROOT" | head -1)

    if [[ -n "$container_id" ]]; then
        local status
        status=$(docker inspect --format='{{.State.Status}}' "$container_id")

        echo ""
        echo "Container ID: $container_id"
        echo "Status: $status"
        echo ""

        if [[ "$status" == "running" ]]; then
            log_info "Container is running"
            echo ""
            docker ps --filter "id=$container_id" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        else
            log_warn "Container exists but is not running"
        fi
    else
        log_warn "No devcontainer found"
        echo ""
        echo "Run './dev.sh build' to create the container"
    fi
}

cmd_logs() {
    local container_id
    container_id=$(docker ps -aq --filter "label=devcontainer.local_folder=$REPO_ROOT" | head -1)

    if [[ -n "$container_id" ]]; then
        log_step "Showing container logs..."
        docker logs "$container_id" "${@:1}"
    else
        log_error "No container found"
        exit 1
    fi
}

main() {
    # Check for devcontainer CLI
    check_devcontainer_cli

    # Parse command
    local command="${1:-}"

    case "$command" in
        build)
            cmd_build
            ;;
        rebuild)
            cmd_rebuild
            ;;
        up)
            cmd_up
            ;;
        shell|sh)
            cmd_shell
            ;;
        exec|run)
            shift
            cmd_exec "$@"
            ;;
        stop)
            cmd_stop
            ;;
        down)
            cmd_down
            ;;
        clean)
            cmd_clean
            ;;
        status)
            cmd_status
            ;;
        logs)
            shift
            cmd_logs "$@"
            ;;
        help|--help|-h|"")
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
