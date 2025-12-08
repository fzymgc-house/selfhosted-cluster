# Windmill Secrets Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Sync secrets directly from Vault to Windmill workspaces via API, keeping secrets out of git.

**Architecture:** Update the sync script to accept workspace targeting, create a GitHub Action for manual/automated triggering, integrate with deploy workflow, and set up Vault AppRole for secure authentication.

**Tech Stack:** Bash, GitHub Actions YAML, Terraform (HCL), Vault API, Windmill API

---

## Task 1: Create Windmill GitOps Tokens in Vault

**Files:**
- None (manual Vault/Windmill operations)

**Step 1: Create staging workspace token in Windmill**

1. Go to https://windmill.fzymgc.house
2. Navigate to workspace `terraform-gitops-staging`
3. Settings → Tokens → Create Token
4. Name: `gitops-sync`, Permissions: write access
5. Copy the token value

**Step 2: Create prod workspace token in Windmill**

1. Navigate to workspace `terraform-gitops-prod`
2. Settings → Tokens → Create Token
3. Name: `gitops-sync`, Permissions: write access
4. Copy the token value

**Step 3: Store tokens in Vault**

```bash
vault kv patch secret/fzymgc-house/cluster/windmill \
  windmill_gitops_staging_token="wm_<staging-token>" \
  windmill_gitops_prod_token="wm_<prod-token>"
```

**Step 4: Verify tokens stored**

```bash
vault kv get secret/fzymgc-house/cluster/windmill | grep windmill_gitops
```

Expected: Both `windmill_gitops_staging_token` and `windmill_gitops_prod_token` listed.

---

## Task 2: Add Vault AppRole for GitHub Actions

**Files:**
- Create: `tf/vault/policy-github-actions.tf`
- Create: `tf/vault/approle-github-actions.tf`

**Step 1: Create policy file**

Create `tf/vault/policy-github-actions.tf`:

```hcl
# SPDX-License-Identifier: MIT

resource "vault_policy" "github_actions" {
  name = "github-actions"

  policy = <<-EOT
    # Read windmill secrets for sync script
    path "secret/data/fzymgc-house/cluster/windmill" {
      capabilities = ["read"]
    }

    # Read GitHub secrets
    path "secret/data/fzymgc-house/cluster/github" {
      capabilities = ["read"]
    }
  EOT
}
```

**Step 2: Create AppRole file**

Create `tf/vault/approle-github-actions.tf`:

```hcl
# SPDX-License-Identifier: MIT

resource "vault_approle_auth_backend_role" "github_actions" {
  backend        = vault_auth_backend.approle.path
  role_name      = "github-actions"
  token_policies = [vault_policy.github_actions.name]

  token_ttl     = 600  # 10 minutes
  token_max_ttl = 1800 # 30 minutes

  # Non-expiring for GitHub secrets storage
  secret_id_ttl      = 0
  secret_id_num_uses = 0
}
```

**Step 3: Verify Terraform syntax**

```bash
cd tf/vault && terraform fmt -check && terraform validate
```

Expected: No errors.

**Step 4: Commit**

```bash
git add tf/vault/policy-github-actions.tf tf/vault/approle-github-actions.tf
git commit -m "feat(vault): add github-actions AppRole for CI/CD workflows"
```

---

## Task 3: Apply Vault AppRole (Manual Step)

**Files:**
- None (Terraform apply)

**Step 1: Plan Terraform changes**

```bash
cd tf/vault && terraform plan -out=tfplan
```

Expected: Shows creation of `vault_policy.github_actions` and `vault_approle_auth_backend_role.github_actions`.

**Step 2: Apply changes**

```bash
cd tf/vault && terraform apply tfplan
```

**Step 3: Get role_id**

```bash
vault read auth/approle/role/github-actions/role-id
```

Save the `role_id` value.

**Step 4: Generate secret_id**

```bash
vault write -f auth/approle/role/github-actions/secret-id
```

Save the `secret_id` value.

**Step 5: Add to GitHub Actions secrets**

1. Go to https://github.com/fzymgc-house/selfhosted-cluster/settings/secrets/actions
2. Add secret: `VAULT_APPROLE_ROLE_ID` = `<role_id>`
3. Add secret: `VAULT_APPROLE_SECRET_ID` = `<secret_id>`

---

## Task 4: Update Sync Script with Workspace Flag

**Files:**
- Modify: `scripts/sync-vault-to-windmill-vars.sh`

**Step 1: Add workspace argument parsing**

Replace lines 5-30 in `scripts/sync-vault-to-windmill-vars.sh`:

```bash
#!/usr/bin/env bash
# Sync secrets from Vault to Windmill workspace variables
set -euo pipefail

WINDMILL_URL="https://windmill.fzymgc.house"
DRY_RUN=false
WORKSPACE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --workspace|-w)
            WORKSPACE="$2"
            shift 2
            ;;
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 --workspace <staging|prod> [--dry-run|-n]"
            echo ""
            echo "Options:"
            echo "  --workspace, -w  Target workspace (required): staging or prod"
            echo "  --dry-run, -n    Show what would be updated without making changes"
            echo "  --help, -h       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate workspace
if [ -z "$WORKSPACE" ]; then
    echo "Error: --workspace is required"
    echo "Use --help for usage information"
    exit 1
fi

case "$WORKSPACE" in
    staging)
        WINDMILL_WORKSPACE="terraform-gitops-staging"
        VAULT_TOKEN_KEY="windmill_gitops_staging_token"
        ;;
    prod)
        WINDMILL_WORKSPACE="terraform-gitops-prod"
        VAULT_TOKEN_KEY="windmill_gitops_prod_token"
        ;;
    *)
        echo "Error: workspace must be 'staging' or 'prod'"
        exit 1
        ;;
esac

echo "=== Sync Vault Secrets to Windmill Variables ==="
echo "Target workspace: $WINDMILL_WORKSPACE"
if $DRY_RUN; then
    echo ">>> DRY RUN MODE - No changes will be made <<<"
fi
echo ""

# Get Windmill token from Vault based on workspace
echo "📦 Getting Windmill token from Vault..."
WINDMILL_TOKEN=$(vault kv get -field="$VAULT_TOKEN_KEY" secret/fzymgc-house/cluster/windmill)
```

**Step 2: Add variable state detection function**

Add after the token retrieval section (before existing `update_variable` function):

```bash
# Function to get variable state
get_variable_state() {
    local var_path=$1
    local new_value=$2
    local is_secret=$3

    # Try to GET the variable from Windmill
    local http_code
    http_code=$(curl -s -w "%{http_code}" -o /tmp/var_response.json \
        "${WINDMILL_URL}/api/w/${WINDMILL_WORKSPACE}/variables/get/${var_path}" \
        -H "Authorization: Bearer ${WINDMILL_TOKEN}" 2>/dev/null)

    if [ "$http_code" = "404" ]; then
        echo "missing"
    elif [ "$is_secret" = "true" ]; then
        # Can't compare secret values - report exists
        echo "exists"
    else
        # Compare non-secret values
        local current
        current=$(jq -r '.value // empty' /tmp/var_response.json 2>/dev/null)
        if [ "$current" = "$new_value" ]; then
            echo "same"
        else
            echo "different"
        fi
    fi
}
```

**Step 3: Update the update_variable function**

Replace the existing `update_variable` function:

```bash
# Function to create/update variable
update_variable() {
    local var_name=$1
    local var_value=$2
    local is_secret=$3
    local description=$4

    # Prepend g/all/ for global variables accessible from all folders
    local var_path="g/all/${var_name}"

    # Get current state
    local state
    state=$(get_variable_state "$var_path" "$var_value" "$is_secret")

    if $DRY_RUN; then
        local display_value
        if [ "$is_secret" = "true" ]; then
            display_value="[REDACTED]"
        else
            display_value="$var_value"
        fi
        case "$state" in
            missing)
                echo "🔍 $var_path: MISSING - would create"
                ;;
            same)
                echo "🔍 $var_path: SAME - would skip"
                ;;
            different)
                echo "🔍 $var_path: DIFFERENT - would update"
                ;;
            exists)
                echo "🔍 $var_path: EXISTS (secret) - would update"
                ;;
        esac
        return
    fi

    # Skip if value is the same (non-secrets only)
    if [ "$state" = "same" ]; then
        echo "⏭️  Skipping $var_path (unchanged)"
        return
    fi

    echo "🔄 Updating variable: $var_path ($state)"

    if [ "$state" = "missing" ]; then
        # Create new variable
        curl -s -X POST \
            "${WINDMILL_URL}/api/w/${WINDMILL_WORKSPACE}/variables/create" \
            -H "Authorization: Bearer ${WINDMILL_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{
                \"path\": \"${var_path}\",
                \"value\": \"${var_value}\",
                \"is_secret\": ${is_secret},
                \"description\": \"${description}\"
            }" > /dev/null
    else
        # Update existing variable
        curl -s -X POST \
            "${WINDMILL_URL}/api/w/${WINDMILL_WORKSPACE}/variables/update/${var_path}" \
            -H "Authorization: Bearer ${WINDMILL_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{
                \"value\": \"${var_value}\",
                \"is_secret\": ${is_secret},
                \"description\": \"${description}\"
            }" > /dev/null
    fi
}
```

**Step 4: Test script locally (dry-run)**

```bash
./scripts/sync-vault-to-windmill-vars.sh --workspace staging --dry-run
```

Expected: Shows state (MISSING/SAME/DIFFERENT/EXISTS) for each variable.

**Step 5: Commit**

```bash
git add scripts/sync-vault-to-windmill-vars.sh
git commit -m "feat(scripts): add workspace targeting and state detection to Windmill sync"
```

---

## Task 5: Create GitHub Action Workflow

**Files:**
- Create: `.github/workflows/sync-windmill-secrets.yaml`

**Step 1: Create the workflow file**

Create `.github/workflows/sync-windmill-secrets.yaml`:

```yaml
# SPDX-License-Identifier: MIT
# yaml-language-server: $schema=https://json.schemastore.org/github-workflow

name: Sync Windmill Secrets

on:
  workflow_dispatch:
    inputs:
      workspace:
        description: 'Target workspace'
        required: true
        type: choice
        options:
          - staging
          - prod
      dry_run:
        description: 'Preview changes without applying'
        required: false
        type: boolean
        default: false
  workflow_call:
    inputs:
      workspace:
        required: true
        type: string
      dry_run:
        required: false
        type: boolean
        default: false
    secrets:
      VAULT_APPROLE_ROLE_ID:
        required: true
      VAULT_APPROLE_SECRET_ID:
        required: true

env:
  VAULT_ADDR: https://vault.fzymgc.house

jobs:
  sync:
    runs-on: fzymgc-house-cluster-runners
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Authenticate to Vault
        uses: hashicorp/vault-action@v3
        with:
          url: ${{ env.VAULT_ADDR }}
          method: approle
          roleId: ${{ secrets.VAULT_APPROLE_ROLE_ID }}
          secretId: ${{ secrets.VAULT_APPROLE_SECRET_ID }}
          exportEnv: true

      - name: Install jq
        run: |
          if ! command -v jq &> /dev/null; then
            apt-get update && apt-get install -y jq
          fi

      - name: Sync secrets to Windmill
        run: |
          chmod +x ./scripts/sync-vault-to-windmill-vars.sh
          ./scripts/sync-vault-to-windmill-vars.sh \
            --workspace ${{ inputs.workspace }} \
            ${{ inputs.dry_run && '--dry-run' || '' }}
```

**Step 2: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/sync-windmill-secrets.yaml'))" && echo "YAML valid"
```

Expected: "YAML valid"

**Step 3: Commit**

```bash
git add .github/workflows/sync-windmill-secrets.yaml
git commit -m "feat(ci): add GitHub Action for Windmill secrets sync"
```

---

## Task 6: Update Deploy Workflow

**Files:**
- Modify: `.github/workflows/windmill-deploy-prod.yaml`

**Step 1: Add sync-secrets job**

Update `.github/workflows/windmill-deploy-prod.yaml` to add the sync job before deploy:

After the `env:` section and before `jobs:`, the jobs section should become:

```yaml
jobs:
  sync-secrets:
    if: github.event.pull_request.merged == true && contains(github.event.pull_request.labels.*.name, 'windmill')
    uses: ./.github/workflows/sync-windmill-secrets.yaml
    with:
      workspace: prod
      dry_run: false
    secrets:
      VAULT_APPROLE_ROLE_ID: ${{ secrets.VAULT_APPROLE_ROLE_ID }}
      VAULT_APPROLE_SECRET_ID: ${{ secrets.VAULT_APPROLE_SECRET_ID }}

  deploy:
    needs: sync-secrets
    if: github.event.pull_request.merged == true && contains(github.event.pull_request.labels.*.name, 'windmill')
    runs-on: fzymgc-house-cluster-runners
    steps:
      # ... existing steps unchanged
```

**Step 2: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/windmill-deploy-prod.yaml'))" && echo "YAML valid"
```

Expected: "YAML valid"

**Step 3: Commit**

```bash
git add .github/workflows/windmill-deploy-prod.yaml
git commit -m "feat(ci): sync secrets before Windmill production deployment"
```

---

## Task 7: Test End-to-End (Manual)

**Step 1: Push feature branch**

```bash
git push -u origin feat/windmill-secrets-sync
```

**Step 2: Create PR**

```bash
gh pr create --title "feat: Windmill secrets sync from Vault" --body "Implements direct Vault → Windmill secret sync, keeping secrets out of git.

## Changes
- Script: Added --workspace flag and state detection
- GitHub Action: Manual trigger + reusable workflow
- Deploy workflow: Syncs secrets before code deploy
- Vault: AppRole for GitHub Actions auth

## Test Plan
- [ ] Manual workflow trigger with dry-run
- [ ] Manual workflow trigger actual sync
- [ ] Merge windmill-staging PR to trigger full flow"
```

**Step 3: Test manual trigger (dry-run)**

1. Go to Actions → Sync Windmill Secrets
2. Click "Run workflow"
3. Select workspace: `staging`, check dry-run: `true`
4. Verify output shows variable states

**Step 4: Test manual trigger (actual)**

1. Run workflow again with dry-run: `false`
2. Verify variables synced to Windmill

**Step 5: Merge and test deploy flow**

1. Merge the PR
2. Make a Windmill change that triggers GitSync
3. Merge the windmill-staging PR
4. Verify sync-secrets job runs before deploy job

---

## Summary

| Task | Description | Estimated Time |
|------|-------------|----------------|
| 1 | Create Windmill tokens in Vault | 5 min |
| 2 | Add Vault AppRole Terraform | 10 min |
| 3 | Apply Vault changes + GH secrets | 10 min |
| 4 | Update sync script | 20 min |
| 5 | Create GitHub Action | 10 min |
| 6 | Update deploy workflow | 10 min |
| 7 | End-to-end testing | 15 min |

**Total: ~80 minutes**
