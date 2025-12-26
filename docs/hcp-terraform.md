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

## Troubleshooting

### Agent not connecting

1. Check agent pod status: `kubectl -n hcp-terraform get pods`
2. Check ExternalSecret: `kubectl -n hcp-terraform get externalsecret`
3. Verify Vault secret exists: `vault kv get secret/fzymgc-house/cluster/hcp-terraform`

### Terraform run errors

1. Check HCP Terraform console for run logs
2. Verify Vault OIDC role exists: `vault read auth/jwt-hcp-terraform/role/tfc-WORKSPACE`
3. Check policy permissions: `vault policy read terraform-WORKSPACE-admin`

## Related

- Design doc: `docs/plans/2025-12-26-hcp-terraform-migration-design.md`
- Agent config: `argocd/app-configs/hcp-terraform-operator/`
- Cloudflare Worker: `cloudflare/workers/hcp-terraform-discord/`
