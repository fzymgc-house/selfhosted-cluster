# Windmill Sync Setup

Guide for setting up Windmill's sync feature to manage workspace as code.

## Overview

Windmill sync allows you to:
- Manage all scripts, flows, and resources as code in Git
- Automatically deploy changes via GitHub Actions
- Version control your entire Windmill workspace
- Pull down existing workspace configuration

## Prerequisites

- Windmill workspace `terraform-gitops` created
- Vault access configured
- GitHub Actions runner deployed (#129)

## Setup Steps

### 1. Create Workspace Token

1. Login to Windmill: https://windmill.fzymgc.house
2. Navigate to workspace: `terraform-gitops`
3. Click your user icon → **Account Settings**
4. Go to **Tokens** tab
5. Click **"New token"**
6. Configure:
   - **Label**: `github-actions-sync`
   - **Expiration**: `No expiration` (or 1 year)
7. Click **"Create token"**
8. **Copy the token immediately** - you won't see it again

### 2. Store Token in Vault

```bash
# Add token to existing Windmill secret
vault kv patch secret/fzymgc-house/cluster/windmill \
  terraform_gitops_token="wm_xxx..."
```

**Verify:**
```bash
vault kv get -field=terraform_gitops_token secret/fzymgc-house/cluster/windmill
```

### 3. Configure Local Windmill CLI

```bash
# Get token from Vault
TOKEN=$(vault kv get -field=terraform_gitops_token secret/fzymgc-house/cluster/windmill)

# Add workspace to wmill CLI
npx windmill-cli workspace add \
  terraform-gitops \
  terraform-gitops \
  https://windmill.fzymgc.house \
  --token "$TOKEN"
```

**Verify configuration:**
```bash
# List configured workspaces
npx windmill-cli workspace list
```

### 4. Pull Existing Workspace

Pull down the current workspace state (including manually created resources):

```bash
cd windmill/

# Pull everything from workspace
npx windmill-cli sync pull \
  --workspace terraform-gitops \
  --token "$TOKEN" \
  --base-url https://windmill.fzymgc.house
```

This creates a directory structure like:
```
windmill/
├── f/              # Flows
├── u/              # User-created items
│   └── admin/      # Your user folder
│       ├── resources/       # Resources (Discord bot, S3, etc.)
│       └── scripts/         # Scripts
├── variables/      # Workspace variables
└── resources/      # Shared resources
```

### 5. Review and Commit

```bash
# Review what was pulled
git status
git diff

# Commit the workspace state
git add windmill/
git commit -m "feat: initial Windmill workspace sync

Pulled existing workspace configuration including manually created resources.

Items synced:
- Workspace structure
- Resources (if any created manually)
- Scripts (if any)
- Variables

Next: Add Terraform automation scripts and flows."
```

## Adding New Resources

Now you can add resources as code instead of manually:

### Discord Bot Resource

**File**: `windmill/u/admin/terraform_discord_bot.resource.json`

```json
{
  "resource_type": "discord_bot_configuration",
  "value": {
    "bot_token": "$var:discord_bot_token",
    "application_id": "$var:discord_application_id",
    "public_key": "$var:discord_public_key",
    "channel_id": "$var:discord_channel_id"
  },
  "description": "Discord bot for Terraform approval notifications"
}
```

### S3 Storage Resource

**File**: `windmill/u/admin/terraform_s3_storage.resource.json`

```json
{
  "resource_type": "s3",
  "value": {
    "bucket": "$var:s3_bucket",
    "region": "us-east-1",
    "endPoint": "$var:s3_endpoint",
    "accessKey": "$var:s3_access_key",
    "secretKey": "$var:s3_secret_key",
    "useSSL": true,
    "pathStyle": false
  },
  "description": "Storj S3 storage for Terraform artifacts"
}
```

### GitHub Token Resource

**File**: `windmill/u/admin/github_token.resource.json`

```json
{
  "resource_type": "github",
  "value": {
    "token": "$var:github_token"
  },
  "description": "GitHub token for repository operations"
}
```

## Setting Up Variables

Resources reference variables using `$var:name` syntax. Create workspace variables:

**File**: `windmill/variables.json`

```json
{
  "discord_bot_token": {
    "value": "",
    "is_secret": true,
    "description": "Discord bot token from Vault"
  },
  "discord_application_id": {
    "value": "",
    "is_secret": false,
    "description": "Discord application ID"
  },
  "discord_public_key": {
    "value": "",
    "is_secret": true,
    "description": "Discord public key for signature verification"
  },
  "discord_channel_id": {
    "value": "",
    "is_secret": false,
    "description": "Discord channel ID for notifications"
  },
  "s3_bucket": {
    "value": "windmill-storage",
    "is_secret": false,
    "description": "S3 bucket name"
  },
  "s3_endpoint": {
    "value": "https://gateway.storjshare.io",
    "is_secret": false,
    "description": "S3 endpoint URL"
  },
  "s3_access_key": {
    "value": "",
    "is_secret": true,
    "description": "S3 access key"
  },
  "s3_secret_key": {
    "value": "",
    "is_secret": true,
    "description": "S3 secret key"
  },
  "github_token": {
    "value": "",
    "is_secret": true,
    "description": "GitHub token for repo access"
  }
}
```

**Note**: Secret values are stored in Windmill, not in Git. The sync only stores the variable definition.

## Pushing Changes

After adding scripts/flows/resources:

```bash
cd windmill/

# Push changes to Windmill
npx windmill-cli sync push \
  --workspace terraform-gitops \
  --token "$TOKEN" \
  --base-url https://windmill.fzymgc.house
```

## GitHub Actions Automation

Create workflow to auto-sync on changes:

**File**: `.github/workflows/windmill-sync.yml`

```yaml
name: Sync Windmill Workspace

on:
  push:
    branches:
      - main
    paths:
      - 'windmill/**'

jobs:
  sync:
    runs-on: windmill-sync
    steps:
      - uses: actions/checkout@v4

      - name: Get Windmill token from Vault
        id: vault
        run: |
          TOKEN=$(vault kv get -field=terraform_gitops_token secret/fzymgc-house/cluster/windmill)
          echo "::add-mask::$TOKEN"
          echo "token=$TOKEN" >> $GITHUB_OUTPUT

      - name: Sync to Windmill
        run: |
          npx windmill-cli sync push \
            --workspace terraform-gitops \
            --token "${{ steps.vault.outputs.token }}" \
            --base-url https://windmill.fzymgc.house \
            --fail-conflicts
        working-directory: windmill/
```

## Workflow

1. **Make changes locally** in `windmill/` directory
2. **Test locally** with `wmill sync push` (optional)
3. **Commit to Git** and push to feature branch
4. **Create PR** for review
5. **Merge to main** - GitHub Actions automatically syncs to Windmill

## Directory Structure

```
windmill/
├── f/                          # Flows
│   └── terraform/
│       ├── deploy_vault.flow/
│       ├── deploy_grafana.flow/
│       └── deploy_authentik.flow/
├── u/                          # User resources
│   └── admin/
│       ├── terraform_discord_bot.resource.json
│       ├── terraform_s3_storage.resource.json
│       ├── github_token.resource.json
│       └── terraform/          # Scripts
│           ├── git_clone.py
│           ├── terraform_init.py
│           ├── terraform_plan.py
│           ├── terraform_apply.py
│           ├── notify_approval.py
│           └── notify_status.py
├── variables.json              # Workspace variables
└── wmill.yaml                 # Workspace metadata
```

## Common Commands

```bash
# Pull workspace
npx windmill-cli sync pull

# Push changes
npx windmill-cli sync push

# Show diff
npx windmill-cli sync diff

# Pull specific folders
npx windmill-cli sync pull --include-path "u/admin"

# Skip pulling scripts (only resources/flows)
npx windmill-cli sync pull --skip-scripts
```

## Troubleshooting

### Token Not Working

```bash
# Verify token is valid
curl -H "Authorization: Bearer $(vault kv get -field=terraform_gitops_token secret/fzymgc-house/cluster/windmill)" \
  https://windmill.fzymgc.house/api/w/terraform-gitops/users/whoami

# Should return user info
```

### Conflicts on Push

```bash
# Pull latest first
npx windmill-cli sync pull

# Resolve conflicts
# Then push
npx windmill-cli sync push --fail-conflicts
```

### Wrong Workspace

```bash
# List workspaces
npx windmill-cli workspace list

# Switch workspace
npx windmill-cli workspace switch terraform-gitops
```

## Security Notes

- **Token**: Stored in Vault, never committed to Git
- **Secrets**: Variable values not synced to Git, only definitions
- **Resources**: Reference variables using `$var:name` syntax
- **GitHub Actions**: Gets token from Vault at runtime

## References

- Windmill CLI Docs: https://www.windmill.dev/docs/advanced/cli
- Sync Documentation: https://www.windmill.dev/docs/advanced/cli/sync
- GitHub Actions Integration: https://www.windmill.dev/docs/advanced/cli/installation
