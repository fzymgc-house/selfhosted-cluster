# Windmill Workspace - Terraform GitOps

This directory contains the Windmill workspace configuration for Terraform automation workflows.

## Overview

- **Workspace**: `terraform-gitops`
- **Instance**: https://windmill.fzymgc.house
- **Purpose**: Automated Terraform plan/apply workflows with Discord notifications and S3 state storage

## Directory Structure

```
windmill/
├── wmill.yaml                    # Workspace sync configuration
├── wmill-lock.yaml              # Lock file (auto-generated)
├── f/                           # Workspace folders
│   ├── terraform/               # Terraform automation scripts
│   │   ├── terraform_init.py           # Initialize Terraform workspace
│   │   ├── terraform_plan.py           # Run terraform plan
│   │   ├── terraform_apply.py          # Run terraform apply
│   │   ├── git_clone.py                # Clone Git repository
│   │   ├── notify_approval.py          # Send approval request to Discord
│   │   ├── notify_status.py            # Send status update to Discord
│   │   ├── test_configuration.py       # Test all integrations
│   │   └── deploy_vault.flow/          # Complete deployment flow
│   ├── resources/               # Shared resources
│   │   ├── s3.resource.yaml            # Cloudflare R2 storage config
│   │   └── github.resource.yaml        # GitHub token
│   └── bots/                    # Discord bot configurations
│       ├── terraform_discord_bot_configuration.resource.yaml
│       └── terraform_discord_bot_token_configuration.resource.yaml
└── c_discord_bot_token_configuration.resource-type.yaml  # Custom resource type
```

## Getting Started

### Prerequisites

1. **Vault Access**: Authenticate to Vault with infrastructure-developer policy
   ```bash
   export VAULT_ADDR=https://vault.fzymgc.house
   vault login
   ```

2. **windmill-cli**: Install globally or use via npx
   ```bash
   npm install -g windmill-cli
   # OR use via npx (no installation needed)
   npx windmill-cli --version
   ```

### Initial Setup

1. **Sync variables from Vault to Windmill**:
   ```bash
   ./scripts/sync-vault-to-windmill-vars.sh
   ```

   This creates workspace variables:
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

2. **Push workspace files to Windmill**:
   ```bash
   cd windmill/
   npx windmill-cli sync push
   ```

3. **Verify integrations**:
   ```bash
   npx windmill-cli script run f/terraform/test_configuration \
     -d '{
       "discord": "$res:f/bots/terraform_discord_bot_configuration",
       "discord_bot_token": "$res:f/bots/terraform_discord_bot_token_configuration",
       "github": "$res:f/resources/github",
       "s3": "$res:f/resources/s3"
     }'
   ```

## Development Workflow

### Syncing Changes

**From Windmill to Local** (pull remote changes):
```bash
npx windmill-cli sync pull
```

**From Local to Windmill** (push local changes):
```bash
npx windmill-cli sync push
```

**Check sync status**:
```bash
npx windmill-cli sync status
```

### Creating New Scripts

1. **Create the script file**:
   ```bash
   # Example: Create a new Python script
   npx windmill-cli script bootstrap f/terraform/my_script python3
   ```

2. **Edit the script**:
   - Write your Python code in `f/terraform/my_script.py`
   - Update the metadata in `f/terraform/my_script.script.yaml`

3. **Push to Windmill**:
   ```bash
   npx windmill-cli sync push
   ```

### Running Scripts Locally

Test scripts via CLI before committing:

```bash
npx windmill-cli script run f/terraform/my_script -d '{"param": "value"}'
```

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

class github(TypedDict):
    token: str

def main(s3: s3, github: github):
    # Resources automatically populated from workspace
    print(f"Using S3 bucket: {s3['bucket']}")
    print(f"GitHub token available: {bool(github['token'])}")
```

**In script metadata** (`script.yaml`):
```yaml
schema:
  properties:
    s3:
      type: object
      format: resource-s3  # References f/resources/s3
    github:
      type: object
      format: resource-github  # References f/resources/github
  required: [s3, github]
```

## Variable Management

### Variable Scoping

All workspace variables use the `g/all/` prefix for global access:

```yaml
# In resource files
value:
  bucket: '$var:g/all/s3_bucket'
  accessKey: '$var:g/all/s3_access_key'
```

### Updating Variables

Variables are managed via Vault, NOT via windmill-cli:

1. Update secret in Vault:
   ```bash
   vault kv patch secret/fzymgc-house/cluster/windmill \
     s3_bucket=new-bucket-name
   ```

2. Re-run sync script:
   ```bash
   ./scripts/sync-vault-to-windmill-vars.sh
   ```

**DO NOT** create `.variable.yaml` files manually - they are managed by the sync script.

## Resource Management

### Creating New Resources

1. **Create resource file**:
   ```yaml
   # f/resources/my_resource.resource.yaml
   description: My custom resource
   value:
     api_key: '$var:g/all/my_api_key'
     endpoint: 'https://api.example.com'
   resource_type: my_resource_type
   ```

2. **Create resource type** (if custom):
   ```yaml
   # my_resource_type.resource-type.yaml
   description: Custom resource type
   schema:
     type: object
     properties:
       api_key:
         type: string
         password: true  # Masked in UI
       endpoint:
         type: string
     required: [api_key, endpoint]
   ```

3. **Push to Windmill**:
   ```bash
   npx windmill-cli sync push
   ```

## Configuration

### wmill.yaml

The workspace sync configuration:

```yaml
workspace: terraform-gitops
version: v2
defaultRuntime: python3

# Sync configuration
skipVariables: true        # Variables managed by Vault sync script
skipResources: false       # Resources synced via CLI
skipResourceTypes: false   # Resource types synced via CLI
skipScripts: false         # Scripts synced via CLI
skipFlows: false          # Flows synced via CLI
includeKey: false         # Don't sync workspace encryption key
```

**Key Points**:
- `skipVariables: true` - Variables are managed by `sync-vault-to-windmill-vars.sh`, not CLI
- Variables in Vault are the source of truth
- Resources, scripts, and flows are managed via Git + CLI sync

## Vault Integration

### Secret Structure

All Windmill secrets stored in Vault at `secret/fzymgc-house/cluster/windmill`:

| Field | Description | Secret? |
|-------|-------------|---------|
| `terraform_gitops_token` | Workspace API token | Yes |
| `discord_bot_token` | Discord bot token | Yes |
| `discord_application_id` | Discord application ID | No |
| `discord_public_key` | Discord public key | Yes |
| `discord_channel_id` | Target Discord channel | No |
| `s3_access_key` | Cloudflare R2 access key | Yes |
| `s3_secret_key` | Cloudflare R2 secret key | Yes |
| `s3_bucket` | R2 bucket name | No |
| `s3_bucket_prefix` | Prefix for organization | No |
| `s3_endpoint` | Cloudflare R2 endpoint | No |

GitHub token stored at `secret/fzymgc-house/cluster/github`:
- `windmill_actions_runner_token` - GitHub PAT for repo access

### Adding New Secrets

1. **Add to Vault**:
   ```bash
   vault kv patch secret/fzymgc-house/cluster/windmill \
     new_secret=value
   ```

2. **Update sync script** (`scripts/sync-vault-to-windmill-vars.sh`):
   ```bash
   NEW_SECRET=$(vault kv get -field=new_secret secret/fzymgc-house/cluster/windmill 2>/dev/null || echo "")
   [ -n "$NEW_SECRET" ] && update_variable "new_secret" "$NEW_SECRET" true "Description"
   ```

3. **Run sync**:
   ```bash
   ./scripts/sync-vault-to-windmill-vars.sh
   ```

4. **Reference in resource**:
   ```yaml
   value:
     secret: '$var:g/all/new_secret'
   ```

## Troubleshooting

### Common Issues

**1. "Not found: Variable {name} not found"**

Variables weren't synced from Vault:
```bash
# Re-run sync script
./scripts/sync-vault-to-windmill-vars.sh

# Verify variables exist
vault kv get secret/fzymgc-house/cluster/windmill
```

**2. "No wmill.yaml found"**

You're running commands from the wrong directory:
```bash
# Always run from windmill/ directory
cd windmill/
npx windmill-cli sync push
```

**3. Resource references not resolving**

Ensure variable paths use `g/all/` prefix:
```yaml
# ✅ Correct
value:
  key: '$var:g/all/my_key'

# ❌ Wrong
value:
  key: '$var:my_key'
```

**4. Sync wants to delete variables**

`skipVariables` should be `true` in `wmill.yaml`:
```yaml
skipVariables: true  # Variables managed by Vault sync script
```

### Testing Resources

Run the test configuration script to verify all integrations:

```bash
npx windmill-cli script run f/terraform/test_configuration \
  -d '{
    "discord": "$res:f/bots/terraform_discord_bot_configuration",
    "discord_bot_token": "$res:f/bots/terraform_discord_bot_token_configuration",
    "github": "$res:f/resources/github",
    "s3": "$res:f/resources/s3"
  }'
```

Expected output:
```json
{
  "overall_success": true,
  "summary": "Discord: ✅, GitHub: ✅, S3: ✅",
  "results": {
    "discord": {"success": true, "tested": true},
    "github": {"success": true, "tested": true},
    "s3": {"success": true, "tested": true}
  }
}
```

## Best Practices

### Scripts

- Use type hints for all parameters
- Define schemas in `.script.yaml` metadata
- Lock dependencies in `.script.lock` files
- Keep scripts focused on single responsibility
- Use resources for credentials, not hardcoded values

### Resources

- Always reference variables, never hardcode secrets
- Use descriptive resource names (e.g., `terraform_discord_bot_configuration`)
- Group related resources in folders (e.g., `f/bots/`, `f/resources/`)
- Document resource purpose in `description` field

### Variables

- Source of truth is Vault, not Windmill
- Use `g/all/` prefix for workspace-wide variables
- Mark secrets as `is_secret: true` in sync script
- Never commit variable values to Git

### Git Workflow

- Test changes locally before committing
- Run `sync push` to verify changes apply cleanly
- Commit both `.py` and `.script.yaml` files together
- Follow conventional commit format
- Create PRs for all changes (never push to main)

## References

- [Windmill Documentation](https://www.windmill.dev/docs)
- [Windmill CLI Sync Guide](https://www.windmill.dev/docs/advanced/cli/sync)
- [Repository CLAUDE.md](../CLAUDE.md) - Development guidelines
- [Completion Summary](../docs/plans/2025-12-07-windmill-migration-completion.md)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review [Windmill Documentation](https://www.windmill.dev/docs)
3. Check GitHub issues: https://github.com/fzymgc-house/selfhosted-cluster/issues
4. Contact: Infrastructure team
