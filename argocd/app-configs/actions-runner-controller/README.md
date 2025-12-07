# Actions Runner Controller

GitHub Actions self-hosted runners for the Windmill migration.

## Purpose

Runs GitHub Actions workflows in the cluster, specifically for:
- Syncing Windmill flows via `wmill sync` on repository changes
- Automated deployment of Windmill configurations

## Components

- **actions-runner-controller**: Controller managing GitHub Actions runner lifecycle
- **windmill-sync-runner**: Runner deployment for `fzymgc-house/selfhosted-cluster` repository

## Required Vault Secrets

Before deployment, configure the GitHub token in Vault:

```bash
# Create a GitHub Personal Access Token (PAT) or GitHub App token with:
# - repo (full control)
# - workflow (update workflows)
# - admin:org (if using org-level runners)

vault kv put secret/fzymgc-house/cluster/github \
  actions_runner_token=<github-pat-or-app-token>
```

### GitHub Token Requirements

**For Personal Access Token:**
- `repo` - Full control of private repositories
- `workflow` - Update GitHub Action workflows

**For GitHub App (Recommended):**
- Repository permissions:
  - Actions: Read & Write
  - Contents: Read
  - Metadata: Read
  - Workflows: Read & Write

## Runner Configuration

The `windmill-sync-runner` deployment:
- **Repository**: `fzymgc-house/selfhosted-cluster`
- **Labels**: `windmill-sync`
- **Mode**: Ephemeral (auto-deleted after each job)
- **Replicas**: 1
- **Resources**:
  - Requests: 512Mi memory, 500m CPU
  - Limits: 1Gi memory, 1000m CPU

## Usage in GitHub Actions

Reference the runner in workflows using the label:

```yaml
name: Sync Windmill
on:
  push:
    paths:
      - 'windmill/**'

jobs:
  sync:
    runs-on: windmill-sync  # Uses our self-hosted runner
    steps:
      - uses: actions/checkout@v4
      - name: Sync to Windmill
        run: |
          npx windmill-cli sync push windmill/
```

## Deployment

Deployed via ArgoCD:
- Application: `actions-runner-controller`
- Sync wave: `0` (early deployment)
- Auto-sync: Enabled

## Monitoring

Check runner status:

```bash
# View controller logs
kubectl --context fzymgc-house logs -n actions-runner-system -l app.kubernetes.io/name=actions-runner-controller

# Check runner pods
kubectl --context fzymgc-house get pods -n actions-runner-system

# View runner deployment status
kubectl --context fzymgc-house get runnerdeployment -n actions-runner-system
```

## Security Considerations

- Runner uses ephemeral mode for security (destroyed after each job)
- Docker-in-Docker enabled for workflow needs
- GitHub token stored in Vault and synced via ExternalSecret
- Runner scoped to specific repository

## References

- [Actions Runner Controller Docs](https://github.com/actions/actions-runner-controller)
- [GitHub Actions Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
