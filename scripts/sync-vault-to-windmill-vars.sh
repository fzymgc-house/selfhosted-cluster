#!/usr/bin/env bash
# Sync secrets from Vault to Windmill workspace variables
set -euo pipefail

WORKSPACE="terraform-gitops"
WINDMILL_URL="https://windmill.fzymgc.house"

echo "=== Sync Vault Secrets to Windmill Variables ==="
echo ""

# Get Windmill token
echo "📦 Getting Windmill token from Vault..."
WINDMILL_TOKEN=$(vault kv get -field=terraform_gitops_token secret/fzymgc-house/cluster/windmill)

# Get all secrets from Vault
echo "📦 Retrieving secrets from Vault..."
DISCORD_BOT_TOKEN=$(vault kv get -field=discord_bot_token secret/fzymgc-house/cluster/windmill 2>/dev/null || echo "")
DISCORD_APP_ID=$(vault kv get -field=discord_application_id secret/fzymgc-house/cluster/windmill 2>/dev/null || echo "")
DISCORD_PUBLIC_KEY=$(vault kv get -field=discord_public_key secret/fzymgc-house/cluster/windmill 2>/dev/null || echo "")
DISCORD_CHANNEL_ID=$(vault kv get -field=discord_channel_id secret/fzymgc-house/cluster/windmill 2>/dev/null || echo "")
S3_ACCESS_KEY=$(vault kv get -field=s3_access_key secret/fzymgc-house/cluster/windmill 2>/dev/null || echo "")
S3_SECRET_KEY=$(vault kv get -field=s3_secret_key secret/fzymgc-house/cluster/windmill 2>/dev/null || echo "")
S3_BUCKET=$(vault kv get -field=s3_bucket secret/fzymgc-house/cluster/windmill 2>/dev/null || echo "")
S3_BUCKET_PREFIX=$(vault kv get -field=s3_bucket_prefix secret/fzymgc-house/cluster/windmill 2>/dev/null || echo "windmill/terraform-gitops")
S3_ENDPOINT=$(vault kv get -field=s3_endpoint secret/fzymgc-house/cluster/windmill 2>/dev/null || echo "")
GITHUB_TOKEN=$(vault kv get -field=windmill_actions_runner_token secret/fzymgc-house/cluster/github 2>/dev/null || echo "")

echo "✅ Secrets retrieved (some may be empty if not configured)"
echo ""

# Function to create/update variable
update_variable() {
    local var_name=$1
    local var_value=$2
    local is_secret=$3
    local description=$4

    echo "🔄 Updating variable: $var_name"

    curl -s -X POST \
        "${WINDMILL_URL}/api/w/${WORKSPACE}/variables/create" \
        -H "Authorization: Bearer ${WINDMILL_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"path\": \"${var_name}\",
            \"value\": \"${var_value}\",
            \"is_secret\": ${is_secret},
            \"description\": \"${description}\"
        }" > /dev/null || true

    # If create failed (already exists), try update
    curl -s -X POST \
        "${WINDMILL_URL}/api/w/${WORKSPACE}/variables/update/${var_name}" \
        -H "Authorization: Bearer ${WINDMILL_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"value\": \"${var_value}\",
            \"is_secret\": ${is_secret},
            \"description\": \"${description}\"
        }" > /dev/null || echo "  (variable may not exist yet)"
}

# Update all variables
echo "📝 Updating Windmill variables..."

[ -n "$DISCORD_BOT_TOKEN" ] && update_variable "discord_bot_token" "$DISCORD_BOT_TOKEN" true "Discord bot token from Vault" || echo "⚠️  Skipping discord_bot_token (not in Vault)"
[ -n "$DISCORD_APP_ID" ] && update_variable "discord_application_id" "$DISCORD_APP_ID" false "Discord application ID" || echo "⚠️  Skipping discord_application_id (not in Vault)"
[ -n "$DISCORD_PUBLIC_KEY" ] && update_variable "discord_public_key" "$DISCORD_PUBLIC_KEY" true "Discord public key for signature verification" || echo "⚠️  Skipping discord_public_key (not in Vault)"
[ -n "$DISCORD_CHANNEL_ID" ] && update_variable "discord_channel_id" "$DISCORD_CHANNEL_ID" false "Discord channel ID for notifications" || echo "⚠️  Skipping discord_channel_id (not in Vault)"
[ -n "$S3_ACCESS_KEY" ] && update_variable "s3_access_key" "$S3_ACCESS_KEY" true "S3 access key" || echo "⚠️  Skipping s3_access_key (not in Vault)"
[ -n "$S3_SECRET_KEY" ] && update_variable "s3_secret_key" "$S3_SECRET_KEY" true "S3 secret key" || echo "⚠️  Skipping s3_secret_key (not in Vault)"
[ -n "$S3_BUCKET" ] && update_variable "s3_bucket" "$S3_BUCKET" false "S3 bucket name" || echo "⚠️  Skipping s3_bucket (not in Vault)"
update_variable "s3_bucket_prefix" "$S3_BUCKET_PREFIX" false "S3 bucket prefix for shared bucket organization"
[ -n "$S3_ENDPOINT" ] && update_variable "s3_endpoint" "$S3_ENDPOINT" false "S3 endpoint URL" || echo "⚠️  Skipping s3_endpoint (not in Vault)"
[ -n "$GITHUB_TOKEN" ] && update_variable "github_token" "$GITHUB_TOKEN" true "GitHub token for repo access" || echo "⚠️  Skipping github_token (not in Vault)"

echo ""
echo "✅ Variables synced (configured secrets only)!"
echo ""
if [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ]; then
    echo "⚠️  WARNING: S3 credentials not configured in Vault"
    echo "   S3 storage tests will fail until credentials are added"
    echo ""
fi
echo "Next: Run test_configuration script in Windmill to verify integrations"
echo ""
