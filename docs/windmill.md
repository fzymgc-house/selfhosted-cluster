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
