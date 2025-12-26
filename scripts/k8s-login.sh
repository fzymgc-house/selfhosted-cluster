#!/usr/bin/env bash
# k8s-login.sh - Authenticate to Kubernetes using Vault-issued certificates
#
# Usage: k8s-login.sh [admin|developer|viewer]
#
# Prerequisites:
#   - vault CLI installed and in PATH
#   - kubectl CLI installed and in PATH
#   - jq installed and in PATH
#   - VAULT_ADDR set (defaults to https://vault.fzymgc.house)
#   - Authenticated to Vault: vault login -method=oidc

set -euo pipefail

ROLE="${1:-viewer}"
CLUSTER="fzymgc-house"
API_SERVER="https://192.168.20.140:6443"
VAULT_PKI_PATH="fzymgc-house/v1/ica1/v1"
TTL="${K8S_CERT_TTL:-8h}"

# Set default VAULT_ADDR if not provided
VAULT_ADDR="${VAULT_ADDR:-https://vault.fzymgc.house}"
export VAULT_ADDR

# Validate role
case "$ROLE" in
  admin|developer|viewer) ;;
  *)
    echo "Usage: k8s-login [admin|developer|viewer]"
    echo ""
    echo "Roles:"
    echo "  admin     - Full cluster-admin access"
    echo "  developer - Read/write workloads (edit role)"
    echo "  viewer    - Read-only access (view role)"
    exit 1
    ;;
esac

# Check prerequisites
command -v vault >/dev/null 2>&1 || { echo "Error: vault CLI not found"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl CLI not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq not found"; exit 1; }

# Check Vault authentication with detailed error reporting
VAULT_CHECK_OUTPUT=$(vault token lookup 2>&1) || {
  echo "Error: Vault authentication check failed"
  echo ""
  if echo "$VAULT_CHECK_OUTPUT" | grep -q "permission denied"; then
    echo "Your token may have expired. Run: vault login -method=oidc"
  elif echo "$VAULT_CHECK_OUTPUT" | grep -q "connection refused\|dial tcp"; then
    echo "Cannot reach Vault server at: $VAULT_ADDR"
    echo "Check your network connection or VAULT_ADDR setting."
  elif echo "$VAULT_CHECK_OUTPUT" | grep -q "sealed"; then
    echo "Vault is sealed. Contact an administrator."
  else
    echo "Details: $VAULT_CHECK_OUTPUT"
    echo ""
    echo "Run: vault login -method=oidc"
  fi
  exit 1
}

# Get username from current Vault token
# Prefer display_name (OIDC login), fallback to entity_id (other auth methods)
USERNAME=$(echo "$VAULT_CHECK_OUTPUT" | jq -r '.data.display_name // .data.entity_id // empty' 2>/dev/null)

if [[ -z "$USERNAME" || "$USERNAME" == "null" ]]; then
  echo "Error: Could not determine username from Vault token"
  echo "Your Vault token may be missing identity information."
  echo "Re-authenticate with: vault login -method=oidc"
  exit 1
fi

echo "Requesting $ROLE certificate for $USERNAME (TTL: $TTL)..."

# Issue certificate from Vault with error handling
CERT_OUTPUT=$(vault write -format=json "$VAULT_PKI_PATH/issue/k8s-$ROLE" \
  common_name="$USERNAME" \
  ttl="$TTL" 2>&1) || {
  echo ""
  echo "Error: Failed to issue $ROLE certificate"
  echo ""
  if echo "$CERT_OUTPUT" | grep -q "permission denied"; then
    echo "You do not have permission to issue $ROLE certificates."
    echo "Ensure you are a member of the 'k8s-${ROLE}s' group in Authentik,"
    echo "then re-authenticate: vault login -method=oidc"
  elif echo "$CERT_OUTPUT" | grep -q "role.*not found\|unknown role"; then
    echo "PKI role 'k8s-$ROLE' does not exist. Contact an administrator."
  elif echo "$CERT_OUTPUT" | grep -q "common_name"; then
    echo "Username '$USERNAME' is not valid for this PKI role."
    echo "Expected format: user@fzymgc.house"
  else
    echo "Vault error: $CERT_OUTPUT"
  fi
  exit 1
}

# Extract cert, key, and CA with validation
CLIENT_CERT=$(echo "$CERT_OUTPUT" | jq -r '.data.certificate // empty')
CLIENT_KEY=$(echo "$CERT_OUTPUT" | jq -r '.data.private_key // empty')
CA_CHAIN=$(echo "$CERT_OUTPUT" | jq -r '.data.ca_chain[0] // empty')

if [[ -z "$CLIENT_CERT" || "$CLIENT_CERT" == "null" ]]; then
  echo "Error: Vault response missing certificate"
  echo "This may indicate a PKI configuration problem. Contact an administrator."
  exit 1
fi

if [[ -z "$CLIENT_KEY" || "$CLIENT_KEY" == "null" ]]; then
  echo "Error: Vault response missing private key"
  echo "This may indicate a PKI configuration problem. Contact an administrator."
  exit 1
fi

if [[ -z "$CA_CHAIN" || "$CA_CHAIN" == "null" ]]; then
  echo "Error: Vault response missing CA chain"
  echo "The PKI issuing CA may not have a configured certificate chain."
  echo "Contact an administrator."
  exit 1
fi

# Create temp files for kubectl (process substitution doesn't work with --embed-certs)
# Files are cleaned up on exit via trap; credentials never persist on disk
CERT_FILE=$(mktemp)
KEY_FILE=$(mktemp)
CA_FILE=$(mktemp)
trap 'rm -f "$CERT_FILE" "$KEY_FILE" "$CA_FILE"' EXIT INT TERM

echo "$CLIENT_CERT" > "$CERT_FILE"
echo "$CLIENT_KEY" > "$KEY_FILE"
echo "$CA_CHAIN" > "$CA_FILE"

# Update kubeconfig with error handling
if ! kubectl config set-cluster "$CLUSTER" \
  --server="$API_SERVER" \
  --certificate-authority="$CA_FILE" \
  --embed-certs=true 2>&1; then
  echo ""
  echo "Error: Failed to configure cluster in kubeconfig"
  echo "Check kubeconfig permissions: ${KUBECONFIG:-$HOME/.kube/config}"
  exit 1
fi

if ! kubectl config set-credentials "$CLUSTER-$ROLE" \
  --client-certificate="$CERT_FILE" \
  --client-key="$KEY_FILE" \
  --embed-certs=true 2>&1; then
  echo ""
  echo "Error: Failed to configure credentials in kubeconfig"
  echo "The certificate data may be malformed. Try re-running the script."
  exit 1
fi

if ! kubectl config set-context "$CLUSTER-$ROLE" \
  --cluster="$CLUSTER" \
  --user="$CLUSTER-$ROLE" 2>&1; then
  echo ""
  echo "Error: Failed to configure context in kubeconfig"
  exit 1
fi

if ! kubectl config use-context "$CLUSTER-$ROLE" 2>&1; then
  echo ""
  echo "Error: Failed to switch to context $CLUSTER-$ROLE"
  exit 1
fi

echo "✓ Configured context: $CLUSTER-$ROLE (expires in $TTL)"
echo ""
echo "Test with: kubectl get nodes"
