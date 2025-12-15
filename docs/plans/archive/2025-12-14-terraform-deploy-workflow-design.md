# Terraform Deploy Workflow Design

## Summary

Create a GitHub Actions workflow that triggers Windmill flows when Terraform module changes are merged to main, along with a generic parameterized Windmill flow that handles all modules.

## Context

The Windmill migration (completed 2025-12-08) created `deploy_vault.flow` for GitOps automation, but no GitHub Action was created to trigger it on merge. Currently, Terraform changes merged to main require manual flow execution in Windmill.

This design creates the missing automation piece.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Workflow pattern | Reusable for all modules | Single source of truth, DRY |
| Authentication | WMILL_TOKEN in GitHub Secrets | Simple, established pattern |
| Trigger | Push to main + manual dispatch | Allows re-runs without new commits |
| Flow input | Commit SHA | Traceability to exact commit |
| Flow design | Generic parameterized | Handles all modules with one flow |
| Existing flow | Delete deploy_vault.flow | Replaced by generic flow |
| Error handling | Fail immediately | Manual re-run via workflow_dispatch |
| Runner | Self-hosted (fzymgc-house-cluster-runners) | Windmill API not externally accessible |

## Components

### GitHub Actions Workflow

**File:** `.github/workflows/terraform-deploy.yml`

**Triggers:**
- Push to `main` with changes in `tf/vault/**`, `tf/grafana/**`, or `tf/authentik/**`
- Manual dispatch with module selection dropdown

**Jobs:**

1. **detect-changes**: Uses `dorny/paths-filter@v3` to determine which modules changed
2. **deploy**: Matrix job that triggers Windmill for each changed module

**API Call:**
```bash
curl -X POST \
  -H "Authorization: Bearer $WMILL_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"module": "<module>", "ref": "<commit-sha>"}' \
  "https://windmill.fzymgc.house/api/w/terraform-gitops-prod/jobs/run/p/f/terraform/deploy_terraform"
```

Uses async `run` endpoint (not `run_wait_result`) - flow handles its own Discord notifications, avoiding GitHub Actions timeout issues for long-running approvals.

### Windmill Flow

**File:** `windmill/f/terraform/deploy_terraform.flow/flow.yaml`

**Input Schema:**
```yaml
schema:
  $schema: 'https://json-schema.org/draft/2020-12/schema'
  type: object
  required: [module, ref]
  properties:
    module:
      type: string
      description: Terraform module path (e.g., tf/vault)
    ref:
      type: string
      description: Git ref to checkout (commit SHA or branch)
```

**Flow Steps:**
1. `git_clone` - Clone repo at specified ref
2. `terraform_init` - Initialize specified module
3. `terraform_plan` - Run plan, check for changes
4. `check_changes` - Branch:
   - Has changes: notify_approval → terraform_apply → notify_success
   - No changes: complete silently
5. `failure_module` - notify_failure on any error

**Changes from deploy_vault.flow:**
- Uses `flow_input.ref` instead of hardcoded `main`
- Uses `flow_input.module` instead of hardcoded `tf/vault`
- Discord notifications include dynamic module name

## Files Changed

### New Files
| File | Purpose |
|------|---------|
| `.github/workflows/terraform-deploy.yml` | Trigger workflow |
| `windmill/f/terraform/deploy_terraform.flow/flow.yaml` | Generic flow |

### Deleted Files
| File | Reason |
|------|--------|
| `windmill/f/terraform/deploy_vault.flow/flow.yaml` | Replaced by generic flow |

### Unchanged
- Existing scripts (`git_clone.py`, `terraform_*.py`, `notify_*.py`) - already parameterized
- `WMILL_TOKEN` secret - already exists

### Excluded Modules
| Module | Reason |
|--------|--------|
| `tf/teleport` | Empty directory - no Terraform files present |
| `tf/cluster-bootstrap` | Chicken-egg problem: this module deploys ArgoCD and Windmill itself. Auto-triggering could break the deployment infrastructure mid-apply. Manual deployment required. |

**Note:** To add a new module, add its path to the workflow's `paths`, `filters`, `matrix`, and `case` statement.

## Implementation

### Workflow File

```yaml
name: Terraform Deploy

on:
  push:
    branches: [main]
    paths:
      - 'tf/vault/**'
      - 'tf/grafana/**'
      - 'tf/authentik/**'
  workflow_dispatch:
    inputs:
      module:
        description: 'Terraform module to deploy'
        required: true
        type: choice
        options:
          - tf/vault
          - tf/grafana
          - tf/authentik

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      vault: ${{ steps.filter.outputs.vault }}
      grafana: ${{ steps.filter.outputs.grafana }}
      authentik: ${{ steps.filter.outputs.authentik }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            vault:
              - 'tf/vault/**'
            grafana:
              - 'tf/grafana/**'
            authentik:
              - 'tf/authentik/**'

  deploy:
    needs: detect-changes
    runs-on: fzymgc-house-cluster-runners
    strategy:
      fail-fast: false
      matrix:
        include:
          - module: tf/vault
            changed: ${{ needs.detect-changes.outputs.vault }}
          - module: tf/grafana
            changed: ${{ needs.detect-changes.outputs.grafana }}
          - module: tf/authentik
            changed: ${{ needs.detect-changes.outputs.authentik }}
    if: |
      needs.detect-changes.outputs.vault == 'true' ||
      needs.detect-changes.outputs.grafana == 'true' ||
      needs.detect-changes.outputs.authentik == 'true' ||
      github.event_name == 'workflow_dispatch'
    steps:
      - name: Trigger Windmill flow
        if: matrix.changed == 'true' || github.event.inputs.module == matrix.module
        env:
          WMILL_TOKEN: ${{ secrets.WMILL_TOKEN }}
        run: |
          echo "Triggering deploy for ${{ matrix.module }} at ${{ github.sha }}"
          curl -sf -X POST \
            -H "Authorization: Bearer $WMILL_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"module": "${{ matrix.module }}", "ref": "${{ github.sha }}"}' \
            "https://windmill.fzymgc.house/api/w/terraform-gitops-prod/jobs/run/p/f/terraform/deploy_terraform"
```

## Testing Plan

1. Deploy the new flow to Windmill via PR to windmill-staging
2. Manually trigger via Windmill UI with `module: tf/vault`, `ref: main` to verify
3. Merge workflow PR, then test with manual dispatch from GitHub Actions
4. Verify end-to-end with a real tf/vault change

## Security Considerations

- `WMILL_TOKEN` is stored as a GitHub secret, not exposed in logs
- Self-hosted runner has network access to Windmill but runs in isolated namespace
- Flow uses existing Vault token for Terraform operations (principle of least privilege)
