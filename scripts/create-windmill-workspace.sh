#!/usr/bin/env bash
# Create Terraform GitOps workspace in Windmill
#
# This script creates the terraform-gitops workspace needed for the migration
# from Argo Events/Workflows to Windmill.

set -euo pipefail

WORKSPACE_ID="terraform-gitops"
WORKSPACE_NAME="Terraform GitOps"
WINDMILL_URL="https://windmill.fzymgc.house"

echo "Creating Windmill workspace: $WORKSPACE_ID"
echo "Workspace name: $WORKSPACE_NAME"
echo ""

# Get admin password from Vault
echo "Retrieving admin password from Vault..."
if ! command -v vault &> /dev/null; then
    echo "ERROR: vault CLI not found. Please install it first."
    exit 1
fi

ADMIN_PASSWORD=$(vault kv get -field=admin_password secret/fzymgc-house/cluster/windmill)

# Check if wmill CLI is available
if ! command -v wmill &> /dev/null && ! command -v npx &> /dev/null; then
    echo "ERROR: Neither wmill CLI nor npx found."
    echo "Please install Node.js to use npx windmill-cli"
    exit 1
fi

echo ""
echo "============================================"
echo "MANUAL STEPS REQUIRED:"
echo "============================================"
echo ""
echo "1. Open Windmill in your browser:"
echo "   $WINDMILL_URL"
echo ""
echo "2. Login with:"
echo "   - Email: admin@windmill.dev (or the configured admin email)"
echo "   - Password: (stored in Vault - use command below to view)"
echo ""
echo "3. Navigate to: Settings → Workspaces → Create Workspace"
echo ""
echo "4. Create workspace with:"
echo "   - Workspace ID: $WORKSPACE_ID"
echo "   - Workspace Name: $WORKSPACE_NAME"
echo ""
echo "5. After creation, create a token:"
echo "   - Go to workspace settings"
echo "   - Create a new token with name: terraform-gitops-automation"
echo "   - Store the token in Vault at:"
echo "     vault kv put secret/fzymgc-house/cluster/windmill \\"
echo "       admin_password=<existing> \\"
echo "       oidc_client_id=<existing> \\"
echo "       oidc_client_secret=<existing> \\"
echo "       terraform_gitops_token=<new-token>"
echo ""
echo "============================================"
echo ""
echo "To view admin password:"
echo "vault kv get -field=admin_password secret/fzymgc-house/cluster/windmill"
echo ""
