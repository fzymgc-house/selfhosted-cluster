# Windmill Secrets Sync Design

## Overview

Sync secrets directly from Vault to Windmill workspaces via API, keeping secrets out of git entirely. Secrets flow: Vault → Script → Windmill API.

## Problem

The current GitSync workflow commits encrypted Windmill variable values to git. While encrypted, this triggered security bot warnings and violates the principle of keeping secrets out of version control.

## Solution

Update the sync script to target either workspace (staging/prod) and integrate it into the deploy workflow. Secrets are synced via API before code deploys.

## Components

### 1. Script Update

**File:** `scripts/sync-vault-to-windmill-vars.sh`

**Changes:**
- Add required `--workspace staging|prod` flag (no default, fail-safe)
- Map workspace to Windmill workspace ID and Vault token key
- Check variable state before updating (only sync if missing/different)
- Enhanced dry-run output showing state: MISSING, SAME, DIFFERENT, EXISTS

**CLI:**
```bash
./scripts/sync-vault-to-windmill-vars.sh --workspace staging
./scripts/sync-vault-to-windmill-vars.sh --workspace prod --dry-run
```

**Variable state detection:**
- GET current value from Windmill API
- 404 = MISSING (will create)
- For secrets: can't compare, show EXISTS (will update)
- For non-secrets: compare values, show SAME or DIFFERENT

### 2. GitHub Action

**File:** `.github/workflows/sync-windmill-secrets.yaml`

**Triggers:**
- `workflow_dispatch` - manual with workspace dropdown and dry-run checkbox
- `workflow_call` - reusable by deploy workflow

**Inputs:**
- `workspace` (required): `staging` or `prod`
- `dry_run` (optional): preview without applying

**Authentication:**
- Uses Vault AppRole via `hashicorp/vault-action@v3`
- Credentials in GitHub secrets: `VAULT_APPROLE_ROLE_ID`, `VAULT_APPROLE_SECRET_ID`

**Runner:** `fzymgc-house-cluster-runners` (has Vault network access)

### 3. Deploy Workflow Integration

**File:** `.github/workflows/windmill-deploy-prod.yaml`

**Updated flow:**
1. PR from windmill-staging merges to main
2. `sync-secrets` job calls the sync workflow with `workspace: prod`
3. `deploy` job (depends on sync-secrets) runs `wmill sync push`

**Fail-safe:** If secret sync fails, deploy is skipped.

### 4. Vault AppRole Setup

**Files:**
- `tf/vault/policy-github-actions.tf`
- `tf/vault/approle-github-actions.tf`

**Policy:** `github-actions`
```hcl
path "secret/data/fzymgc-house/cluster/windmill" {
  capabilities = ["read"]
}

path "secret/data/fzymgc-house/cluster/github" {
  capabilities = ["read"]
}
```

**AppRole:** `github-actions`
- Token TTL: 10 minutes
- Token max TTL: 30 minutes
- Non-expiring secret_id for GitHub secrets storage

**Manual steps after Terraform apply:**
1. Get role_id: `vault read auth/approle/role/github-actions/role-id`
2. Generate secret_id: `vault write -f auth/approle/role/github-actions/secret-id`
3. Add to GitHub Actions secrets: `VAULT_APPROLE_ROLE_ID`, `VAULT_APPROLE_SECRET_ID`

### 5. Windmill Token Storage

**Vault path:** `secret/fzymgc-house/cluster/windmill`

**Keys:**
- `windmill_gitops_staging_token` - API token for staging workspace
- `windmill_gitops_prod_token` - API token for prod workspace

**Token creation:**
1. Windmill → Settings → Tokens → Create token with workspace write access
2. Store in Vault:
```bash
vault kv patch secret/fzymgc-house/cluster/windmill \
  windmill_gitops_staging_token="wm_..." \
  windmill_gitops_prod_token="wm_..."
```

## Implementation Order

1. Create Windmill tokens and store in Vault
2. Add Vault AppRole via Terraform
3. Update sync script with workspace flag and state detection
4. Create GitHub Action workflow
5. Update deploy workflow to call sync first
6. Add AppRole credentials to GitHub secrets
7. Test: manual trigger with dry-run, then actual sync

## Security Considerations

- Secrets never committed to git
- AppRole has minimal read-only access to specific paths
- Short-lived tokens (10 min TTL)
- Fail-safe: missing workspace flag = error (no accidental runs)
