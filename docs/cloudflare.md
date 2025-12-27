# Cloudflare

Cloudflare integration for DNS, Tunnels, and Workers.

## Overview

| Component | Location |
|-----------|----------|
| Terraform module | `tf/cloudflare/` |
| Workers | `cloudflare/workers/` |
| API tokens | Vault: `secret/fzymgc-house/infrastructure/cloudflare/*` |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Cloudflare Account                         │
├─────────────────┬─────────────────┬─────────────────────────────┤
│ fzymgc.house    │ fzymgc.net      │ Workers                     │
│ (internal DNS)  │ (webhooks)      │ (serverless functions)      │
├─────────────────┴─────────────────┴─────────────────────────────┤
│                     Zero Trust Tunnel                           │
│                   fzymgc-house-main                             │
└─────────────────────────────────────────────────────────────────┘
```

## API Token Pattern

Currently uses a single bootstrap token with full operational permissions.

> **Note**: Cloudflare provider v5 has [breaking changes](https://github.com/cloudflare/terraform-provider-cloudflare/issues/5062)
> for `cloudflare_api_token` that make Terraform-managed token creation unreliable.
> When v5 stabilizes, we'll add a two-token pattern (bootstrap → workload).

| Token | Purpose | Permissions | Created By |
|-------|---------|-------------|------------|
| Bootstrap | Terraform auth + operations | Full operational | Manual (once) |

### Vault Paths

| Path | Content |
|------|---------|
| `.../cloudflare/bootstrap-token` | Bootstrap token for Terraform |
| `.../cloudflare/discord-webhook` | Discord webhook URL |
| `.../cloudflare/hcp-terraform-hmac` | HMAC secret for webhook validation |

### Bootstrap Token Setup (One-Time)

1. Create token in [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens):
   - **API Tokens** → **Create Token** → **Create Custom Token**
   - Permissions:
     - Account > Workers Scripts > Edit
     - Account > Cloudflare Tunnel > Edit
     - Account > Account Settings > Read
     - Zone > DNS > Edit
     - Zone > Zone > Read
   - Account/Zone Resources: Include your account and all zones

2. Store in Vault:
   ```bash
   vault kv put secret/fzymgc-house/infrastructure/cloudflare/bootstrap-token \
     token="YOUR_BOOTSTRAP_TOKEN"
   ```

3. Apply Terraform:
   ```bash
   terraform -chdir=tf/cloudflare apply
   ```

## Resources Managed

### Tunnels (`tunnel.tf`)

| Resource | Purpose |
|----------|---------|
| `cloudflare_zero_trust_tunnel_cloudflared.main` | Main tunnel |
| `cloudflare_zero_trust_tunnel_cloudflared_config.main` | Ingress routing |
| `cloudflare_dns_record.webhook_services` | CNAME records for webhooks |

Webhook services (configured via `var.webhook_services`):
- `windmill-wh.fzymgc.net` → Windmill webhooks

### Workers (`workers.tf`)

| Worker | Purpose |
|--------|---------|
| `hcp-terraform-discord` | HCP Terraform → Discord notifications |

Worker URL: `https://hcp-terraform-discord.<subdomain>.workers.dev`

### API Tokens (`api-tokens.tf`)

Creates a scoped workload token and stores it in Vault for external systems.

## Applying Changes

### Order of Operations

```
tf/vault → tf/cloudflare → Configure HCP TF webhook
```

1. **tf/vault**: Creates HMAC secret
2. **tf/cloudflare**: Deploys Worker with HMAC binding, creates workload token
3. **HCP TF UI**: Add HMAC token to notification webhook

### Apply Commands

```bash
# Standard apply (via HCP Terraform)
# Triggered automatically on PR merge

# Manual apply (break-glass)
terraform -chdir=tf/cloudflare plan
terraform -chdir=tf/cloudflare apply
```

See `tf/cloudflare/MANUAL_APPLY.md` for detailed break-glass procedure.

## Workers

### HCP Terraform Discord Worker

Transforms HCP Terraform notification webhooks into Discord embeds.

| Property | Value |
|----------|-------|
| Code | `cloudflare/workers/hcp-terraform-discord/worker.js` |
| Terraform | `tf/cloudflare/workers.tf` |
| Secrets | `DISCORD_WEBHOOK_URL`, `HMAC_SECRET` |

**HMAC Validation**: When `HMAC_SECRET` is configured, validates `X-TFE-Notification-Signature` header. Invalid signatures rejected with 401.

## Troubleshooting

### Token Authentication Errors

```
Error: 403 Forbidden - Authentication error
```

**Cause**: API token missing required permissions.

**Fix**:
1. Check bootstrap token has all required permissions
2. Verify token is stored correctly in Vault:
   ```bash
   vault kv get secret/fzymgc-house/infrastructure/cloudflare/bootstrap-token
   ```

### Tunnel Not Connecting

```bash
# Check tunnel status
kubectl -n cloudflared get pods
kubectl -n cloudflared logs -l app.kubernetes.io/name=cloudflared

# Verify credentials in Vault
vault kv get secret/fzymgc-house/cluster/cloudflared/tunnels/fzymgc-house-main
```

### Worker Deployment Fails

```bash
# Check Worker exists
curl -X GET "https://api.cloudflare.com/client/v4/accounts/ACCOUNT_ID/workers/scripts" \
  -H "Authorization: Bearer $(vault kv get -field=token secret/fzymgc-house/infrastructure/cloudflare/bootstrap-token)"
```

## Related

- Tunnel connector: `argocd/app-configs/cloudflared-main/`
- Worker code: `cloudflare/workers/hcp-terraform-discord/`
- HCP Terraform docs: `docs/hcp-terraform.md`
