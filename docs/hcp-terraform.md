# HCP Terraform

Terraform execution via HCP Terraform self-hosted agents.

## Overview

| Component | Location |
|-----------|----------|
| Workspaces | `tf/hcp-terraform/` manages all workspace configuration |
| Agent | Kubernetes pod in `hcp-terraform` namespace |
| Notifications | Cloudflare Worker -> Discord |
| Secrets | Vault OIDC authentication |

## Architecture

```
GitHub PR -> HCP Terraform -> Agent Pod -> Vault OIDC -> Terraform Apply
                |
        Cloudflare Worker -> Discord
```

## Workspaces

| Workspace | Directory | Purpose |
|-----------|-----------|---------|
| vault | tf/vault | Vault configuration, policies, auth |
| authentik | tf/authentik | Authentik SSO configuration |
| grafana | tf/grafana | Grafana dashboards and config |
| cloudflare | tf/cloudflare | DNS and tunnel configuration |
| core-services | tf/core-services | Core K8s service configuration |
| cluster-bootstrap | tf/cluster-bootstrap | Initial cluster infrastructure |

## Workflow

1. **PR Created**: Speculative plan runs, results posted as PR comment
2. **PR Merged**: Plan + auto-apply executes
3. **Notifications**: Discord receives status updates via webhook

## Vault Authentication

Workspaces authenticate to Vault via OIDC workload identity:

- JWT auth backend: `jwt-hcp-terraform`
- Per-workspace roles: `tfc-vault`, `tfc-authentik`, `tfc-grafana`, `tfc-cloudflare`, `tfc-core-services`
- Policies grant least-privilege access per workspace

**Note:** `cluster-bootstrap` runs locally with `VAULT_TOKEN` (not via HCP TF agent) because it deploys the operator itself.

## Agent Deployment

The HCP Terraform Operator manages agent pods:

- **Namespace**: `hcp-terraform`
- **Operator**: HashiCorp HCP Terraform Operator (Helm)
- **Agent Pool CRD**: `fzymgc-house-agents`
- **Token**: Stored in Vault at `secret/fzymgc-house/cluster/hcp-terraform`

## Discord Notifications

Cloudflare Worker transforms HCP Terraform webhooks to Discord embeds.

| Component | Location |
|-----------|----------|
| Worker code | `cloudflare/workers/hcp-terraform-discord/` |
| Secret management | `tf/cloudflare/workers.tf` |
| Webhook URL | Vault: `secret/fzymgc-house/infrastructure/cloudflare/discord-webhook` |

### Setup

Create the Discord webhook secret in Vault (one-time, can copy from Windmill):

```bash
# Copy from existing Windmill config
WEBHOOK=$(vault kv get -field=discord_webhook_url secret/fzymgc-house/cluster/windmill)
vault kv put secret/fzymgc-house/infrastructure/cloudflare/discord-webhook url="$WEBHOOK"

# Or create new webhook from Discord channel settings
vault kv put secret/fzymgc-house/infrastructure/cloudflare/discord-webhook \
  url="https://discord.com/api/webhooks/..."
```

After applying `tf/cloudflare`, the Worker secret is automatically configured.

### Worker Deployment

Deploy the Worker via wrangler (initial deploy or code updates):

```bash
cd cloudflare/workers/hcp-terraform-discord
npx wrangler deploy
```

The Worker secret is managed by Terraform - no manual `wrangler secret` commands needed.

### Optional HMAC Validation

For enhanced security, configure HMAC signature validation:

1. Generate a random token:
   ```bash
   TOKEN=$(openssl rand -hex 32)
   vault kv put secret/fzymgc-house/infrastructure/cloudflare/hcp-terraform-hmac token="$TOKEN"
   ```

2. Add the token to your HCP TF notification configuration (UI or API)

3. Update `tf/cloudflare/workers.tf` to include the `HMAC_SECRET` binding

When `HMAC_SECRET` is configured, the Worker validates the `X-TFE-Notification-Signature` header. Without it, requests are accepted without signature verification.

## Troubleshooting

### Agent not connecting

1. Check agent pod status: `kubectl -n hcp-terraform get pods`
2. Check ExternalSecret: `kubectl -n hcp-terraform get externalsecret`
3. Verify Vault secret exists: `vault kv get secret/fzymgc-house/cluster/hcp-terraform`

### Terraform run errors

1. Check HCP Terraform console for run logs
2. Verify Vault OIDC role exists: `vault read auth/jwt-hcp-terraform/role/tfc-WORKSPACE`
3. Check policy permissions: `vault policy read terraform-WORKSPACE-admin`

### OIDC authentication failures

Common OIDC issues and resolutions:

| Error | Cause | Fix |
|-------|-------|-----|
| `role not found` | Missing JWT role in Vault | Create role: `vault write auth/jwt-hcp-terraform/role/tfc-WORKSPACE ...` |
| `claim not in bound_claims` | Workspace name mismatch | Check `bound_claims_value` matches HCP TF workspace name |
| `token expired` | JWT past validity window | Verify clocks are synced; tokens valid 5 minutes |
| `permission denied` | Policy missing capabilities | Check policy grants access to required paths |

Debug OIDC authentication:

```bash
# Verify JWT auth backend exists
vault auth list | grep jwt-hcp-terraform

# Check role configuration
vault read auth/jwt-hcp-terraform/role/tfc-WORKSPACE

# Verify bound claims (must match HCP TF workspace exactly)
vault read -field=bound_claims auth/jwt-hcp-terraform/role/tfc-WORKSPACE

# Test policy access
vault policy read terraform-WORKSPACE-admin
```

For `cluster-bootstrap` workspace: OIDC is intentionally excluded (deploys the operator itself). Run locally with `VAULT_TOKEN` environment variable.

### cluster-bootstrap Circular Dependency

The `cluster-bootstrap` workspace **cannot** use the HCP TF agent because:

1. It deploys the HCP Terraform Operator itself
2. The operator must exist before agent pods can run
3. Chicken-and-egg: agent needs operator, operator needs workspace to run

**Solution:** Run `cluster-bootstrap` locally with `VAULT_TOKEN`:

```bash
export VAULT_TOKEN=$(vault token create -field=token -policy=terraform-cluster-bootstrap-admin)
terraform -chdir=tf/cluster-bootstrap apply
```

## Maintenance

### Agent Token Rotation

The agent token (`tfe_agent_token`) doesn't auto-rotate. To rotate manually:

```bash
# 1. Taint the token resource to force recreation
terraform -chdir=tf/hcp-terraform taint tfe_agent_token.k8s

# 2. Apply to generate new token
terraform -chdir=tf/hcp-terraform apply

# 3. Update Vault secret with new token
vault kv put secret/fzymgc-house/cluster/hcp-terraform \
  agent_token="$(terraform -chdir=tf/hcp-terraform output -raw agent_token)"

# 4. ExternalSecret will sync automatically, restart agent if needed
kubectl -n hcp-terraform rollout restart deployment/fzymgc-house-agents
```

### Rollback to Windmill

If HCP Terraform fails post-migration:

1. Scale down operator: `kubectl -n hcp-terraform scale deployment hcp-terraform-operator --replicas=0`
2. Re-enable Windmill flows in `windmill/f/terraform/`
3. Remove HCP TF workspace variables in HCP TF UI (restore local execution)

## Related

- Design doc: `docs/plans/2025-12-26-hcp-terraform-migration-design.md`
- Agent config: `argocd/app-configs/hcp-terraform-operator/`
- Cloudflare Worker: `cloudflare/workers/hcp-terraform-discord/`
