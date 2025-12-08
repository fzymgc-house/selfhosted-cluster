#!/usr/bin/env bash
# Sync secrets from Vault to Windmill workspace variables
set -euo pipefail

WINDMILL_URL="https://windmill.fzymgc.house"
DRY_RUN=false
WORKSPACE=""

# Create temp file for API responses (cleaned up on exit)
TEMP_RESPONSE=$(mktemp)
trap 'rm -f "$TEMP_RESPONSE"' EXIT

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --workspace|-w)
            WORKSPACE="$2"
            shift 2
            ;;
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 --workspace <staging|prod> [--dry-run|-n]"
            echo ""
            echo "Options:"
            echo "  --workspace, -w  Target workspace (required): staging or prod"
            echo "  --dry-run, -n    Show what would be updated without making changes"
            echo "  --help, -h       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate workspace
if [ -z "$WORKSPACE" ]; then
    echo "Error: --workspace is required"
    echo "Use --help for usage information"
    exit 1
fi

case "$WORKSPACE" in
    staging)
        WINDMILL_WORKSPACE="terraform-gitops-staging"
        ;;
    prod)
        WINDMILL_WORKSPACE="terraform-gitops-prod"
        ;;
    *)
        echo "Error: workspace must be 'staging' or 'prod'"
        exit 1
        ;;
esac

echo "=== Sync Vault Secrets to Windmill Variables ==="
echo "Target workspace: $WINDMILL_WORKSPACE"
if $DRY_RUN; then
    echo ">>> DRY RUN MODE - No changes will be made <<<"
fi
echo ""

# Get Windmill token from Vault (single token works for all workspaces - tokens are per-user)
echo "📦 Getting Windmill token from Vault..."
if ! WINDMILL_TOKEN=$(vault kv get -field=windmill_gitops_token secret/fzymgc-house/cluster/windmill 2>&1); then
    echo "❌ Failed to get Windmill token from Vault"
    echo "   Error: $WINDMILL_TOKEN"
    echo "   Ensure VAULT_TOKEN is set and has access to secret/fzymgc-house/cluster/windmill"
    exit 1
fi

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
VAULT_TERRAFORM_TOKEN=$(vault kv get -field=vault_terraform_token secret/fzymgc-house/cluster/windmill 2>/dev/null || echo "")

echo "✅ Secrets retrieved (some may be empty if not configured)"
echo ""

# Function to get variable state
get_variable_state() {
    local var_path=$1
    local new_value=$2
    local is_secret=$3

    # Try to GET the variable from Windmill
    local http_code
    http_code=$(curl -s -w "%{http_code}" -o "$TEMP_RESPONSE" \
        "${WINDMILL_URL}/api/w/${WINDMILL_WORKSPACE}/variables/get/${var_path}" \
        -H "Authorization: Bearer ${WINDMILL_TOKEN}" 2>/dev/null)

    if [ "$http_code" = "404" ]; then
        echo "missing"
    elif [ "$http_code" != "200" ]; then
        echo "error"
    elif [ "$is_secret" = "true" ]; then
        # Can't compare secret values - report exists
        echo "exists"
    else
        # Compare non-secret values
        local current
        current=$(jq -r '.value // empty' "$TEMP_RESPONSE" 2>/dev/null)
        if [ "$current" = "$new_value" ]; then
            echo "same"
        else
            echo "different"
        fi
    fi
}

# Function to create/update variable
update_variable() {
    local var_name=$1
    local var_value=$2
    local is_secret=$3
    local description=$4

    # Prepend g/all/ for global variables accessible from all folders
    local var_path="g/all/${var_name}"

    # Get current state
    local state
    state=$(get_variable_state "$var_path" "$var_value" "$is_secret")

    if $DRY_RUN; then
        local display_value
        if [ "$is_secret" = "true" ]; then
            display_value="[REDACTED]"
        else
            display_value="$var_value"
        fi
        case "$state" in
            missing)
                echo "🔍 $var_path: MISSING - would create"
                ;;
            same)
                echo "🔍 $var_path: SAME - would skip"
                ;;
            different)
                echo "🔍 $var_path: DIFFERENT - would update"
                ;;
            exists)
                echo "🔍 $var_path: EXISTS (secret) - would update"
                ;;
            error)
                echo "🔍 $var_path: ERROR checking state - would attempt create"
                ;;
        esac
        return
    fi

    # Skip if value is the same (non-secrets only)
    if [ "$state" = "same" ]; then
        echo "⏭️  Skipping $var_path (unchanged)"
        return
    fi

    echo "🔄 Updating variable: $var_path ($state)"

    local http_code
    if [ "$state" = "missing" ] || [ "$state" = "error" ]; then
        # Create new variable
        http_code=$(curl -s -w "%{http_code}" -o "$TEMP_RESPONSE" -X POST \
            "${WINDMILL_URL}/api/w/${WINDMILL_WORKSPACE}/variables/create" \
            -H "Authorization: Bearer ${WINDMILL_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{
                \"path\": \"${var_path}\",
                \"value\": \"${var_value}\",
                \"is_secret\": ${is_secret},
                \"description\": \"${description}\"
            }")
        if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
            echo "   ⚠️  Create failed (HTTP $http_code), trying update..."
            # Fall through to update
            http_code=$(curl -s -w "%{http_code}" -o "$TEMP_RESPONSE" -X POST \
                "${WINDMILL_URL}/api/w/${WINDMILL_WORKSPACE}/variables/update/${var_path}" \
                -H "Authorization: Bearer ${WINDMILL_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "{
                    \"value\": \"${var_value}\",
                    \"is_secret\": ${is_secret},
                    \"description\": \"${description}\"
                }")
        fi
    else
        # Update existing variable
        http_code=$(curl -s -w "%{http_code}" -o "$TEMP_RESPONSE" -X POST \
            "${WINDMILL_URL}/api/w/${WINDMILL_WORKSPACE}/variables/update/${var_path}" \
            -H "Authorization: Bearer ${WINDMILL_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{
                \"value\": \"${var_value}\",
                \"is_secret\": ${is_secret},
                \"description\": \"${description}\"
            }")
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        echo "   ❌ Failed to update $var_path (HTTP $http_code)"
    fi
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
[ -n "$VAULT_TERRAFORM_TOKEN" ] && update_variable "vault_terraform_token" "$VAULT_TERRAFORM_TOKEN" true "Vault token for Terraform operations" || echo "⚠️  Skipping vault_terraform_token (not in Vault)"

echo ""
echo "✅ Variables synced to $WINDMILL_WORKSPACE!"
echo ""
if [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ]; then
    echo "⚠️  WARNING: S3 credentials not configured in Vault"
    echo "   S3 storage tests will fail until credentials are added"
    echo ""
fi
echo "Next: Run test_configuration script in Windmill to verify integrations"
echo ""
