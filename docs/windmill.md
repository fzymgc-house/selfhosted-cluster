# Windmill

Terraform GitOps automation platform replacing Argo Events/Workflows.

## Architecture

Two-workspace pattern with Git-based promotion:

| Workspace | Branch | Purpose |
|-----------|--------|---------|
| `terraform-gitops-staging` | `staging` | Development/testing, Git sync enabled |
| `terraform-gitops-prod` | `main` | Production, deployed via GitHub Actions |

**Deployment flow:** staging → PR → main → auto-deploy to prod

## Configuration

### Vault Secrets

All Windmill secrets stored at `secret/fzymgc-house/cluster/windmill`:

| Key | Purpose |
|-----|---------|
| `terraform_gitops_token` | Workspace sync token |
| `discord_bot_token` | Discord notifications |
| `discord_application_id` | Discord app ID |
| `discord_channel_id` | Notification channel |
| `s3_access_key` | Cloudflare R2 access |
| `s3_secret_key` | Cloudflare R2 secret |
| `s3_bucket` | R2 bucket name |
| `s3_endpoint` | R2 endpoint URL |

### Resources

| Resource Path | Type | Purpose |
|--------------|------|---------|
| `u/admin/terraform_discord_bot` | discord_bot_configuration | Approval notifications |
| `u/admin/terraform_s3_storage` | s3 | Terraform artifacts |
| `u/admin/github_token` | github | Repository access |

## Directory Structure

```
windmill/
├── wmill.yaml              # Workspace config
├── f/terraform/            # Flows and scripts
│   ├── deploy_terraform.flow/
│   ├── git_clone.py
│   ├── terraform_init.py
│   ├── terraform_plan.py
│   ├── terraform_apply.py
│   ├── notify_approval.py
│   └── notify_status.py
├── u/admin/                # Resources
└── variables.json          # Variable definitions
```

## GitHub Actions

| Workflow | Trigger | Action |
|----------|---------|--------|
| `windmill-deploy-prod.yaml` | PR merge to main with `windmill` label | Deploy to prod workspace |
| `sync-windmill-secrets.yaml` | Manual/scheduled | Sync Vault secrets to Windmill |

## Sync Commands

```bash
# Configure workspace
npx wmill workspace add terraform-gitops-staging terraform-gitops-staging \
  https://windmill.fzymgc.house "$TOKEN"

# Push changes
npx wmill sync push --workspace terraform-gitops-staging

# Pull remote state
npx wmill sync pull

# Show diff
npx wmill sync diff
```

## Deploy Flow

The `deploy_terraform` flow executes these steps:

1. Clone repository at specified ref
2. Initialize Terraform for specified module
3. Run plan and upload plan artifact to S3
4. If changes: send Discord notification, wait for approval, download plan from S3, apply
5. If no changes: complete silently

### Plan Staleness Protection

To prevent "Saved plan is stale" errors:

| Mechanism | Purpose |
|-----------|---------|
| **Concurrency control** | `concurrent_limit: 1` per module prevents parallel runs |
| **S3 plan storage** | Plan files stored in S3 with Windmill's `WM_JOB_ID`, not shared workspace |
| **Plan cleanup** | Plans deleted from S3 after successful apply |

Plan S3 key format: `terraform-plans/{module--path}/{WM_JOB_ID}/tfplan`

Example: `tf/vault` → `terraform-plans/tf--vault/abc123-def456/tfplan`

Note: Path separators are replaced with `--` to prevent collisions (e.g., `tf/vault` vs `tf-vault`).

### S3 Lifecycle Policy (Recommended)

Configure a lifecycle rule on the S3 bucket to auto-expire orphaned plans as a safety net:

```json
{
  "Rules": [
    {
      "ID": "expire-terraform-plans",
      "Filter": { "Prefix": "terraform-plans/" },
      "Status": "Enabled",
      "Expiration": { "Days": 7 }
    }
  ]
}
```

This catches plans from failed flows, timeouts, or cleanup failures.

## Terraform Modules

Supported modules for automated deployment:

| Module | Path | Description |
|--------|------|-------------|
| Vault | `tf/vault` | Policies and configuration |
| Grafana | `tf/grafana` | Dashboards and data sources |
| Authentik | `tf/authentik` | Applications and groups |
| Cloudflare | `tf/cloudflare` | DNS and tunnel config |
| Core Services | `tf/core-services` | Core services config |

**Excluded:** `tf/cluster-bootstrap` (deploys Windmill itself)

## Troubleshooting

### Token Validation
```bash
curl -H "Authorization: Bearer $TOKEN" \
  https://windmill.fzymgc.house/api/w/terraform-gitops/users/whoami
```

### Worker Logs
```bash
kubectl --context fzymgc-house logs -n windmill -l app=windmill-workers --tail=100
```

### Discord Issues
- Verify bot has "Send Messages" permission in channel
- Check channel ID is correct (Developer Mode → Copy ID)
- Validate token: `curl -H "Authorization: Bot $TOKEN" https://discord.com/api/v10/users/@me`
