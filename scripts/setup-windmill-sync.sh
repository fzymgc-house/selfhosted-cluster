#!/usr/bin/env bash
# Setup Windmill sync and pull workspace configuration
set -euo pipefail

WORKSPACE="terraform-gitops"
WINDMILL_URL="https://windmill.fzymgc.house"

echo "=== Windmill Sync Setup ==="
echo ""

# Check prerequisites
if ! command -v vault &> /dev/null; then
    echo "❌ ERROR: vault CLI not found"
    exit 1
fi

if ! command -v npx &> /dev/null; then
    echo "❌ ERROR: npx not found (need Node.js)"
    exit 1
fi

# Get token from Vault
echo "📦 Retrieving token from Vault..."
TOKEN=$(vault kv get -field=terraform_gitops_token secret/fzymgc-house/cluster/windmill 2>&1)

if [[ "$TOKEN" == *"not present"* ]] || [[ "$TOKEN" == *"No value found"* ]]; then
    echo ""
    echo "❌ Token not found in Vault"
    echo ""
    echo "Please create a token in Windmill:"
    echo "1. Go to: $WINDMILL_URL"
    echo "2. Navigate to workspace: $WORKSPACE"
    echo "3. Account Settings → Tokens → New token"
    echo "4. Label: github-actions-sync"
    echo "5. Store in Vault:"
    echo ""
    echo "   vault kv patch secret/fzymgc-house/cluster/windmill \\"
    echo "     terraform_gitops_token=<your-token>"
    echo ""
    exit 1
fi

echo "✅ Token found"

# Configure workspace
echo "🔧 Configuring Windmill CLI workspace..."
npx windmill-cli workspace add \
    "$WORKSPACE" \
    "$WORKSPACE" \
    "$WINDMILL_URL" \
    --token "$TOKEN" 2>/dev/null || true

echo "✅ Workspace configured"

# Create windmill directory
mkdir -p windmill
cd windmill

# Pull workspace
echo "⬇️  Pulling workspace configuration..."
npx windmill-cli sync pull \
    --workspace "$WORKSPACE" \
    --token "$TOKEN" \
    --base-url "$WINDMILL_URL" \
    --yes

echo ""
echo "✅ Workspace synced successfully!"
echo ""
echo "📁 Workspace contents:"
find . -type f | head -20
echo ""
echo "Next steps:"
echo "1. Review pulled configuration: cd windmill && ls -la"
echo "2. Add Terraform scripts and flows"
echo "3. Commit to Git: git add windmill/ && git commit"
echo "4. Push changes: npx windmill-cli sync push"
echo ""
