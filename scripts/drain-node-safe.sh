#!/usr/bin/env bash
# SPDX-License-Identifier: MIT-0
# Script to safely drain a Kubernetes node by handling Longhorn instance manager PDBs
#
# This script checks if it's safe to delete Longhorn instance manager PDBs before draining a node.
# Safety checks include:
# - Verifying all volumes have at least 2 healthy replicas
# - Checking that volumes are not in degraded state
# - Ensuring no volume operations are in progress

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] <node-name>

Safely drain a Kubernetes node by checking Longhorn volume health and
removing PodDisruptionBudgets if safe.

OPTIONS:
    -c, --context <context>    Kubernetes context to use (default: current context)
    -f, --force                Skip safety checks (dangerous!)
    -d, --dry-run              Show what would be done without making changes
    -h, --help                 Show this help message

EXAMPLES:
    # Safely drain a node
    $0 tpi-alpha-2

    # Dry run to see what would happen
    $0 --dry-run tpi-alpha-2

    # Use specific kubectl context
    $0 --context prod-cluster worker-node-1

SAFETY CHECKS:
    - All volumes must have at least 2 healthy replicas
    - No volumes in degraded/faulted state
    - No volume rebuilding operations in progress
    - All attached volumes must be healthy

EOF
    exit 0
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Default values
KUBE_CONTEXT=""
FORCE=false
DRY_RUN=false
NODE_NAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--context)
            KUBE_CONTEXT="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            if [[ -z "$NODE_NAME" ]]; then
                NODE_NAME="$1"
            else
                log_error "Too many arguments"
                usage
            fi
            shift
            ;;
    esac
done

if [[ -z "$NODE_NAME" ]]; then
    log_error "Node name is required"
    usage
fi

# Build kubectl command
KUBECTL="kubectl"
if [[ -n "$KUBE_CONTEXT" ]]; then
    KUBECTL="kubectl --context $KUBE_CONTEXT"
fi

log_info "Checking node '$NODE_NAME'..."

# Verify node exists
if ! $KUBECTL get node "$NODE_NAME" &>/dev/null; then
    log_error "Node '$NODE_NAME' not found"
    exit 1
fi

# Check if node is already drained
if $KUBECTL get node "$NODE_NAME" -o jsonpath='{.spec.unschedulable}' | grep -q true; then
    log_info "Node is already cordoned"
else
    log_info "Node is not cordoned yet"
fi

# Find instance manager pods on this node
log_info "Finding Longhorn instance managers on node '$NODE_NAME'..."
INSTANCE_MANAGERS=$($KUBECTL get pods -n longhorn-system \
    -l longhorn.io/component=instance-manager \
    --field-selector spec.nodeName="$NODE_NAME" \
    -o jsonpath='{.items[*].metadata.name}')

if [[ -z "$INSTANCE_MANAGERS" ]]; then
    log_info "No instance managers found on node '$NODE_NAME'"
    log_info "Node can be drained normally"
    exit 0
fi

log_info "Found instance managers: $INSTANCE_MANAGERS"

# Get corresponding PDBs
PDBS=()
for im in $INSTANCE_MANAGERS; do
    if $KUBECTL get pdb -n longhorn-system "$im" &>/dev/null; then
        PDBS+=("$im")
    fi
done

if [[ ${#PDBS[@]} -eq 0 ]]; then
    log_info "No PodDisruptionBudgets found for instance managers"
    log_info "Node can be drained normally"
    exit 0
fi

log_info "Found ${#PDBS[@]} PDB(s): ${PDBS[*]}"

# Safety checks (unless --force)
if [[ "$FORCE" == "false" ]]; then
    log_info "Performing safety checks..."

    # Check volumes on this node
    log_info "Checking volumes attached to node '$NODE_NAME'..."
    VOLUMES=$($KUBECTL get volumes -n longhorn-system -o json | \
        jq -r --arg node "$NODE_NAME" \
        '.items[] | select(.status.currentNodeID == $node) | .metadata.name')

    if [[ -n "$VOLUMES" ]]; then
        log_info "Found volumes on node:"
        echo "$VOLUMES" | while read -r vol; do
            echo "  - $vol"
        done

        # Check volume health
        UNHEALTHY=false
        while read -r vol; do
            STATE=$($KUBECTL get volume -n longhorn-system "$vol" -o jsonpath='{.status.state}')
            ROBUSTNESS=$($KUBECTL get volume -n longhorn-system "$vol" -o jsonpath='{.status.robustness}')
            REPLICA_COUNT=$($KUBECTL get volume -n longhorn-system "$vol" -o jsonpath='{.spec.numberOfReplicas}')

            log_info "  Volume $vol: state=$STATE robustness=$ROBUSTNESS replicas=$REPLICA_COUNT"

            if [[ "$ROBUSTNESS" != "healthy" ]] && [[ "$ROBUSTNESS" != "unknown" ]]; then
                log_error "  Volume $vol is not healthy (robustness: $ROBUSTNESS)"
                UNHEALTHY=true
            fi

            if [[ "$STATE" == "attached" ]] && [[ "$REPLICA_COUNT" -lt 2 ]]; then
                log_error "  Volume $vol has less than 2 replicas ($REPLICA_COUNT)"
                UNHEALTHY=true
            fi
        done <<< "$VOLUMES"

        if [[ "$UNHEALTHY" == "true" ]]; then
            log_error "Safety check failed: Unhealthy volumes detected"
            log_error "Use --force to bypass safety checks (not recommended)"
            exit 1
        fi

        log_info "All volumes are healthy"
    else
        log_info "No volumes currently attached to this node"
    fi

    # Check for volume rebuilding operations
    log_info "Checking for active volume operations..."
    REBUILDING=$($KUBECTL get volumes -n longhorn-system -o json | \
        jq -r --arg node "$NODE_NAME" \
        '[.items[] | select(.status.currentNodeID == $node and .status.isStandby == false and .status.rebuildStatus != null)] | length')

    if [[ "$REBUILDING" -gt 0 ]]; then
        log_error "Safety check failed: $REBUILDING volume(s) are rebuilding"
        log_error "Wait for rebuild to complete or use --force to bypass"
        exit 1
    fi

    log_info "No active volume operations detected"
    log_info "✓ All safety checks passed"
else
    log_warn "Skipping safety checks (--force enabled)"
fi

# Delete PDBs
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would delete the following PDBs:"
    for pdb in "${PDBS[@]}"; do
        echo "  - $pdb"
    done
    log_info "[DRY RUN] Would then drain node '$NODE_NAME'"
    exit 0
fi

log_info "Deleting PodDisruptionBudgets..."
for pdb in "${PDBS[@]}"; do
    log_info "  Deleting PDB: $pdb"
    $KUBECTL delete pdb -n longhorn-system "$pdb"
done

log_info "✓ PDBs deleted successfully"
log_info ""
log_info "Node is ready to drain. Run:"
log_info "  $KUBECTL drain $NODE_NAME --ignore-daemonsets --delete-emptydir-data"
log_info ""
log_info "After maintenance, uncordon the node:"
log_info "  $KUBECTL uncordon $NODE_NAME"
