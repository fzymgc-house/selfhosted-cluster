#!/usr/bin/env bash
# k8s-login.sh - Authenticate to Kubernetes using Vault-issued certificates
#
# Usage: k8s-login.sh [admin|developer|viewer]
#
# Prerequisites:
#   - vault CLI installed and in PATH
#   - kubectl CLI installed and in PATH
#   - jq installed and in PATH
#   - Authenticated to Vault: vault login -method=oidc

set -euo pipefail

ROLE="${1:-viewer}"
CLUSTER="fzymgc-house"
API_SERVER="https://192.168.20.140:6443"
VAULT_PKI_PATH="fzymgc-house/v1/ica1/v1"
TTL="${K8S_CERT_TTL:-8h}"

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

# Check Vault authentication
if ! vault token lookup >/dev/null 2>&1; then
  echo "Error: Not authenticated to Vault"
  echo "Run: vault login -method=oidc"
  exit 1
fi

# Get username from current Vault token
USERNAME=$(vault token lookup -format=json | jq -r '.data.display_name // .data.entity_id')

echo "Requesting $ROLE certificate for $USERNAME (TTL: $TTL)..."

# Issue certificate from Vault
CERT_DATA=$(vault write -format=json "$VAULT_PKI_PATH/issue/k8s-$ROLE" \
  common_name="$USERNAME" \
  ttl="$TTL")

# Extract cert, key, and CA
CLIENT_CERT=$(echo "$CERT_DATA" | jq -r '.data.certificate')
CLIENT_KEY=$(echo "$CERT_DATA" | jq -r '.data.private_key')
CA_CHAIN=$(echo "$CERT_DATA" | jq -r '.data.ca_chain[0]')

# Create temp files for kubectl (process substitution doesn't work with --embed-certs)
CERT_FILE=$(mktemp)
KEY_FILE=$(mktemp)
CA_FILE=$(mktemp)
trap "rm -f $CERT_FILE $KEY_FILE $CA_FILE" EXIT

echo "$CLIENT_CERT" > "$CERT_FILE"
echo "$CLIENT_KEY" > "$KEY_FILE"
echo "$CA_CHAIN" > "$CA_FILE"

# Update kubeconfig
kubectl config set-cluster "$CLUSTER" \
  --server="$API_SERVER" \
  --certificate-authority="$CA_FILE" \
  --embed-certs=true

kubectl config set-credentials "$CLUSTER-$ROLE" \
  --client-certificate="$CERT_FILE" \
  --client-key="$KEY_FILE" \
  --embed-certs=true

kubectl config set-context "$CLUSTER-$ROLE" \
  --cluster="$CLUSTER" \
  --user="$CLUSTER-$ROLE"

kubectl config use-context "$CLUSTER-$ROLE"

echo "Configured context: $CLUSTER-$ROLE (expires in $TTL)"
echo ""
echo "Test with: kubectl get nodes"
