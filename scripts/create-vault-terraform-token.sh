#!/usr/bin/env bash
# Generate Vault orphan token for Terraform operations
set -euo pipefail

echo "=== Create Vault Terraform Token ==="
echo ""

# Check Vault authentication
if ! vault token lookup &>/dev/null; then
    echo "ERROR: Not authenticated to Vault"
    echo "Please run: vault login"
    exit 1
fi

echo "✅ Vault authentication verified"
echo ""

# Check required policy exists
if ! vault policy read admin &>/dev/null; then
    echo "ERROR: 'admin' policy not found in Vault"
    echo "Please apply Terraform configuration in tf/vault first"
    exit 1
fi

echo "✅ Admin policy exists"
echo ""

# Generate orphan token with admin policy
echo "🔐 Generating Vault orphan token for Terraform operations..."
echo "   Policy: admin"
echo "   TTL: 0 (non-expiring)"
echo "   Renewable: true"
echo ""

TOKEN_JSON=$(vault token create \
    -orphan \
    -policy=admin \
    -ttl=0 \
    -renewable=true \
    -display-name="terraform-windmill" \
    -format=json)

TOKEN=$(echo "$TOKEN_JSON" | jq -r '.auth.client_token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "ERROR: Failed to create token"
    exit 1
fi

echo "✅ Token created successfully"
echo "   Token: ${TOKEN:0:8}..." # Show only first 8 chars
echo ""

# Store token in Vault
echo "💾 Storing token in Vault..."
vault kv patch secret/fzymgc-house/cluster/windmill vault_terraform_token="$TOKEN"

echo "✅ Token stored at: secret/fzymgc-house/cluster/windmill"
echo "   Key: vault_terraform_token"
echo ""

# Verify storage
STORED_TOKEN=$(vault kv get -field=vault_terraform_token secret/fzymgc-house/cluster/windmill)
if [ "$STORED_TOKEN" = "$TOKEN" ]; then
    echo "✅ Token verified in Vault storage"
else
    echo "⚠️  WARNING: Token verification failed"
fi

echo ""
echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Run: ./scripts/sync-vault-to-windmill-vars.sh"
echo "  2. Verify token synced to Windmill variable: g/all/vault_terraform_token"
echo ""
echo "⚠️  IMPORTANT: This token has full admin access to Vault"
echo "    Keep it secure and rotate it periodically"
echo ""
