# Windmill Migration - Completion Summary

**Date**: December 7, 2025
**Status**: Phase 1 Complete ✅

## Overview

Successfully migrated Terraform automation from Argo Workflows to Windmill, establishing proper workspace configuration, variable synchronization from Vault, and resource management via windmill-cli.

## Completed Work

### 1. Workspace Setup ✅

**Issue**: [#128](https://github.com/fzymgc-house/selfhosted-cluster/issues/128)

- ✅ Created `terraform-gitops` workspace at https://windmill.fzymgc.house
- ✅ Generated API token for CLI sync operations
- ✅ Stored workspace token in Vault: `secret/fzymgc-house/cluster/windmill` (field: `terraform_gitops_token`)
- ✅ Configured workspace for Python 3.11 as default runtime

### 2. Directory Structure ✅

**Issue**: [#132](https://github.com/fzymgc-house/selfhosted-cluster/issues/132)

Created organized directory structure in `windmill/`:

```
windmill/
├── wmill.yaml                    # Workspace sync configuration
├── wmill-lock.yaml              # Lock file for synced resources
├── f/                           # Workspace folders
│   ├── terraform/               # Terraform automation scripts
│   │   ├── terraform_init.py
│   │   ├── terraform_plan.py
│   │   ├── terraform_apply.py
│   │   ├── git_clone.py
│   │   ├── notify_approval.py
│   │   ├── notify_status.py
│   │   ├── test_configuration.py
│   │   └── deploy_vault.flow/   # Terraform deployment flow
│   ├── resources/               # Shared resources
│   │   ├── s3.resource.yaml
│   │   └── github.resource.yaml
│   └── bots/                    # Discord bot configurations
│       ├── terraform_discord_bot_configuration.resource.yaml
│       └── terraform_discord_bot_token_configuration.resource.yaml
└── scripts/
    └── sync-vault-to-windmill-vars.sh  # Vault → Windmill sync script
```

**Key Configuration** (`wmill.yaml`):
- Skip variables (managed by Vault sync script)
- Sync resources, scripts, flows, folders
- Exclude workspace encryption key from sync
- Default to Python 3.11 runtime

### 3. S3 Storage Integration ✅

**Issue**: [#130](https://github.com/fzymgc-house/selfhosted-cluster/issues/130)

**Implementation**: Cloudflare R2 instead of Storj

- ✅ Created S3 resource: `f/resources/s3.resource.yaml`
- ✅ Configured Cloudflare R2 credentials in Vault
- ✅ Created global variables with `g/all/` prefix:
  - `g/all/s3_access_key`
  - `g/all/s3_secret_key`
  - `g/all/s3_bucket` → `fzymgc-cluster-storage`
  - `g/all/s3_bucket_prefix` → `windmill-terraform`
  - `g/all/s3_endpoint` → Cloudflare R2 endpoint
- ✅ Tested successfully: File upload/download working

**Vault Secret Path**: `secret/fzymgc-house/cluster/windmill`

### 4. Discord Notifications ✅

**Issue**: [#131](https://github.com/fzymgc-house/selfhosted-cluster/issues/131)

- ✅ Created Discord bot resources:
  - `f/bots/terraform_discord_bot_configuration.resource.yaml`
  - `f/bots/terraform_discord_bot_token_configuration.resource.yaml`
- ✅ Configured Discord credentials in Vault:
  - `discord_bot_token`
  - `discord_application_id`
  - `discord_public_key`
  - `discord_channel_id`
- ✅ Created global variables with `g/all/` prefix
- ✅ Fixed channel permissions (initial 403 error resolved)
- ✅ Tested successfully: Messages posting to Discord channel

**Vault Secret Paths**:
- Bot credentials: `secret/fzymgc-house/cluster/windmill`
- Webhook URL also available: `discord_webhook_url`

### 5. Resource Management ✅

**Issue**: [#136](https://github.com/fzymgc-house/selfhosted-cluster/issues/136)

Created typed resources with variable references:

**Resources Created**:
- ✅ `f/resources/s3.resource.yaml` (type: `s3`)
- ✅ `f/resources/github.resource.yaml` (type: `github`)
- ✅ `f/bots/terraform_discord_bot_configuration.resource.yaml` (type: `discord_bot_configuration`)
- ✅ `f/bots/terraform_discord_bot_token_configuration.resource.yaml` (type: `c_discord_bot_token_configuration`)

**Resource Type Created**:
- ✅ `discord_bot_configuration.resource-type.yaml` (custom type for Discord bot config)

**Variable References**: All resources use `$var:g/all/{variable_name}` syntax to reference global workspace variables

### 6. Vault Integration ✅

**Script**: `scripts/sync-vault-to-windmill-vars.sh`

Automated synchronization of secrets from HashiCorp Vault to Windmill workspace variables:

**Variables Synced**:
- `g/all/discord_bot_token`
- `g/all/discord_application_id`
- `g/all/discord_public_key`
- `g/all/discord_channel_id`
- `g/all/s3_access_key`
- `g/all/s3_secret_key`
- `g/all/s3_bucket`
- `g/all/s3_bucket_prefix`
- `g/all/s3_endpoint`
- `g/all/github_token`

**Key Implementation Details**:
- Variables created with `g/all/` prefix for global access
- Proper handling of secrets (marked as `is_secret: true`)
- Idempotent: Creates or updates variables
- Source of truth: Vault secrets at `secret/fzymgc-house/cluster/windmill`

## Technical Solutions

### Variable Path Requirements

**Problem**: Windmill variables require folder-scoped paths (e.g., `g/all/variable_name`), not simple names.

**Solution**:
- Updated sync script to prepend `g/all/` prefix to all variables
- Updated all resource files to reference `$var:g/all/{name}` format
- Configured `skipVariables: true` in `wmill.yaml` (variables managed by sync script, not CLI)

**Error Fixed**: SQL constraint error `"proper_id"` when creating variables with invalid paths

### windmill-cli Sync Configuration

**Approach**: Use windmill-cli for code/resource sync, Vault sync script for variables

**Configuration** (`wmill.yaml`):
```yaml
skipVariables: true        # Managed by sync script
skipResources: false       # Synced via CLI
skipResourceTypes: false   # Synced via CLI
skipScripts: false         # Synced via CLI
skipFlows: false          # Synced via CLI
includeKey: false         # Don't sync workspace encryption key
```

### Resource Type System

Created custom resource type for Discord bot configuration to support structured validation:

```yaml
# discord_bot_configuration.resource-type.yaml
schema:
  properties:
    application_id: {type: string, nullable: false}
    bot_token: {type: string, password: true}
    public_key: {type: string, nullable: false}
  required: [application_id, public_key, bot_token]
```

## Test Results

**Script**: `f/terraform/test_configuration.py`

Final test results (all integrations working):

```
✅ Discord: Success - Message posted to channel
✅ GitHub: Success - Repository access confirmed
✅ S3 (Cloudflare R2): Success - File upload/download tested

Overall: PASSED
```

## Vault Secret Structure

All Windmill secrets stored in Vault at:

### `secret/fzymgc-house/cluster/windmill`

| Field | Description | Used By |
|-------|-------------|---------|
| `terraform_gitops_token` | Workspace API token | windmill-cli, sync script |
| `discord_bot_token` | Discord bot token | Discord resources |
| `discord_application_id` | Discord application ID | Discord resources |
| `discord_public_key` | Discord public key | Discord resources |
| `discord_channel_id` | Target Discord channel | Discord resources |
| `discord_webhook_url` | Discord webhook URL | Alternative to bot |
| `s3_access_key` | Cloudflare R2 access key | S3 resource |
| `s3_secret_key` | Cloudflare R2 secret key | S3 resource |
| `s3_bucket` | R2 bucket name | S3 resource |
| `s3_bucket_prefix` | Prefix for organization | S3 resource |
| `s3_endpoint` | Cloudflare R2 endpoint | S3 resource |

### `secret/fzymgc-house/cluster/github`

| Field | Description | Used By |
|-------|-------------|---------|
| `windmill_actions_runner_token` | GitHub PAT for repo access | GitHub resource |

## Workflow Integration

### Using Resources in Scripts

Resources are automatically injected as typed parameters:

```python
from typing import TypedDict

class s3(TypedDict):
    bucket: str
    region: str
    endPoint: str
    accessKey: str
    secretKey: str
    useSSL: bool
    pathStyle: bool

def main(s3: s3):
    # S3 config automatically populated from f/resources/s3
    bucket_name = s3["bucket"]
    ...
```

### Script Metadata Format

All scripts follow standardized metadata:

```yaml
# script.yaml
summary: ''
description: ''
lock: '!inline script.lock'  # Dependencies lock file
kind: script
schema:
  $schema: 'https://json-schema.org/draft/2020-12/schema'
  type: object
  properties:
    s3:
      type: object
      format: resource-s3  # References f/resources/s3.resource.yaml
  required: [s3]
```

## Git Commits

1. **feat(windmill): configure sync and create resource definitions** (`34fa92a`)
   - Updated wmill.yaml to enable resource/variable sync
   - Created S3, GitHub, Discord resource definitions
   - All resources reference workspace variables using `$var:` syntax

2. **fix(windmill): use global variables with g/all/ prefix for resources** (`cb943de`)
   - Fixed variable path format (g/all/ prefix required)
   - Updated sync script to create global variables
   - Set skipVariables: true in wmill.yaml
   - All integrations tested and working

## Next Steps

### Immediate

- [x] Update GitHub issues to reflect completion
- [ ] Create documentation for developers on using Windmill resources
- [ ] Document Terraform workflow patterns

### Future Enhancements

**Issue**: [#148](https://github.com/fzymgc-house/selfhosted-cluster/issues/148)
- Create Grafana dashboards for Windmill observability
- Monitor workflow execution metrics
- Track resource usage and costs

### Migration from Argo Workflows

- Migrate existing Terraform automation workflows to Windmill
- Update CI/CD pipelines to trigger Windmill flows
- Deprecate Argo Workflows Terraform automation

## Lessons Learned

### Windmill Variable Scoping

**Learning**: Windmill requires all variables to be scoped to a folder path.

- Workspace-level variables don't exist as simple names
- Use `g/all/` prefix for variables accessible from all folders
- Resources reference variables with `$var:g/all/{name}` syntax

### CLI vs API Management

**Approach**: Split responsibilities between windmill-cli and Vault sync

- **windmill-cli**: Manages code (scripts, flows, resources)
- **Vault sync script**: Manages variables (secrets from Vault)
- **wmill.yaml**: Configured with `skipVariables: true` to prevent conflicts

### Resource Type System

**Best Practice**: Define custom resource types for structured data validation

- Provides type safety in scripts
- Enforces required fields
- Supports sensitive field masking (password: true)

## References

- Windmill Documentation: https://www.windmill.dev/docs
- Windmill CLI Sync: https://www.windmill.dev/docs/advanced/cli/sync
- Repository: https://github.com/fzymgc-house/selfhosted-cluster
- Windmill Instance: https://windmill.fzymgc.house
- Workspace: `terraform-gitops`

## Related Issues

- #128: Create Windmill workspace ✅
- #130: Configure Windmill S3 storage integration ✅
- #131: Configure Discord notifications for Windmill ✅
- #132: Set up Windmill directory structure ✅
- #136: Create Windmill resources for secrets ✅
- #148: Create Grafana dashboards for Windmill (Future)
