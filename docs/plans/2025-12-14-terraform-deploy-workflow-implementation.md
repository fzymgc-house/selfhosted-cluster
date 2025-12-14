# Terraform Deploy Workflow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create GitHub Actions workflow that triggers Windmill flows when Terraform module changes merge to main.

**Architecture:** A reusable GitHub Actions workflow detects changes in `tf/vault`, `tf/grafana`, or `tf/authentik` directories and triggers a generic parameterized Windmill flow via API. The flow accepts `module` and `ref` parameters, replacing the hardcoded `deploy_vault.flow`.

**Tech Stack:** GitHub Actions, Windmill flows (YAML), curl for API calls

---

## Task 1: Create Generic Windmill Flow

**Files:**
- Create: `windmill/f/terraform/deploy_terraform.flow/flow.yaml`

**Step 1: Create flow directory**

```bash
mkdir -p windmill/f/terraform/deploy_terraform.flow
```

**Step 2: Write the flow file**

Create `windmill/f/terraform/deploy_terraform.flow/flow.yaml`:

```yaml
summary: Deploy Terraform module with approval
description: |
  Generic deployment flow for any Terraform module:
  1. Clone repository at specified ref
  2. Initialize Terraform for specified module
  3. Run plan and check for changes
  4. If changes: send Discord notification, wait for approval, apply
  5. If no changes: complete silently

  Inputs:
  - module: Terraform module path (e.g., tf/vault)
  - ref: Git ref to checkout (commit SHA or branch)
schema:
  $schema: 'https://json-schema.org/draft/2020-12/schema'
  type: object
  required:
    - module
    - ref
  properties:
    module:
      type: string
      description: Terraform module path (e.g., tf/vault, tf/grafana, tf/authentik)
    ref:
      type: string
      description: Git ref to checkout (commit SHA or branch name)
value:
  same_worker: true
  modules:
    - id: git_clone
      value:
        type: script
        input_transforms:
          branch:
            type: javascript
            expr: flow_input.ref
          github:
            type: javascript
            expr: resource('f/resources/github')
          repository:
            type: static
            value: fzymgc-house/selfhosted-cluster
          workspace_dir:
            type: static
            value: /tmp/terraform-workspace
        path: f/terraform/git_clone
    - id: terraform_init
      value:
        type: script
        input_transforms:
          module_path:
            type: javascript
            expr: flow_input.module
          s3:
            type: javascript
            expr: resource('f/resources/s3')
          s3_bucket_prefix:
            type: javascript
            expr: variable('g/all/s3_bucket_prefix')
          tfc_token:
            type: javascript
            expr: variable('g/all/tfc_token')
          workspace_path:
            type: javascript
            expr: results.git_clone.workspace_path
        path: f/terraform/terraform_init
    - id: terraform_plan
      value:
        type: script
        input_transforms:
          module_dir:
            type: javascript
            expr: results.terraform_init.module_dir
          tfc_token:
            type: javascript
            expr: variable('g/all/tfc_token')
          vault_addr:
            type: static
            value: 'https://vault.fzymgc.house'
          vault_token:
            type: javascript
            expr: variable('g/all/vault_terraform_token')
        path: f/terraform/terraform_plan
    - id: check_changes
      value:
        type: branchone
        branches:
          - summary: Has changes - request approval and apply
            expr: results.terraform_plan.has_changes
            modules:
              - id: notify_approval
                value:
                  type: script
                  input_transforms:
                    discord:
                      type: javascript
                      expr: resource('f/bots/terraform_discord_bot_configuration')
                    discord_bot_token:
                      type: javascript
                      expr: resource('f/bots/terraform_discord_bot_token_configuration')
                    module:
                      type: javascript
                      expr: flow_input.module
                    plan_details:
                      type: javascript
                      expr: results.terraform_plan.plan_details
                    plan_summary:
                      type: javascript
                      expr: results.terraform_plan.plan_summary
                  path: f/terraform/notify_approval
                suspend:
                  required_events: 1
                  timeout: 86400
              - id: terraform_apply
                value:
                  type: script
                  input_transforms:
                    module_dir:
                      type: javascript
                      expr: results.terraform_init.module_dir
                    tfc_token:
                      type: javascript
                      expr: variable('g/all/tfc_token')
                    vault_addr:
                      type: static
                      value: 'https://vault.fzymgc.house'
                    vault_token:
                      type: javascript
                      expr: variable('g/all/vault_terraform_token')
                  path: f/terraform/terraform_apply
              - id: notify_success
                value:
                  type: script
                  input_transforms:
                    approval_message_id:
                      type: javascript
                      expr: results.notify_approval?.message_id
                    details:
                      type: static
                      value: Terraform apply completed successfully
                    discord:
                      type: javascript
                      expr: resource('f/bots/terraform_discord_bot_configuration')
                    discord_bot_token:
                      type: javascript
                      expr: resource('f/bots/terraform_discord_bot_token_configuration')
                    module:
                      type: javascript
                      expr: flow_input.module
                    status:
                      type: static
                      value: success
                  path: f/terraform/notify_status
        default: []
  failure_module:
    id: notify_failure
    value:
      type: script
      input_transforms:
        approval_message_id:
          type: javascript
          expr: results.notify_approval?.message_id
        details:
          type: javascript
          expr: error.message
        discord:
          type: javascript
          expr: resource('f/bots/terraform_discord_bot_configuration')
        discord_bot_token:
          type: javascript
          expr: resource('f/bots/terraform_discord_bot_token_configuration')
        module:
          type: javascript
          expr: flow_input.module
        status:
          type: static
          value: failed
      path: f/terraform/notify_status
```

**Step 3: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('windmill/f/terraform/deploy_terraform.flow/flow.yaml'))" && echo "YAML valid"
```

Expected: `YAML valid`

**Step 4: Commit the new flow**

```bash
git add windmill/f/terraform/deploy_terraform.flow/
git commit -m "feat(windmill): Add generic deploy_terraform flow

Parameterized flow accepting module and ref inputs, replacing
module-specific flows. Supports tf/vault, tf/grafana, tf/authentik.

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Create GitHub Actions Workflow

**Files:**
- Create: `.github/workflows/terraform-deploy.yml`

**Step 1: Write the workflow file**

Create `.github/workflows/terraform-deploy.yml`:

```yaml
# Triggers Windmill terraform deployment flows when tf/* modules change
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
    if: github.event_name == 'push'
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
    runs-on: fzymgc-house-cluster-runners
    needs: [detect-changes]
    if: always() && (needs.detect-changes.result == 'success' || needs.detect-changes.result == 'skipped')
    strategy:
      fail-fast: false
      matrix:
        module: [tf/vault, tf/grafana, tf/authentik]
    steps:
      - name: Check if should deploy
        id: should-deploy
        run: |
          if [ "${{ github.event_name }}" == "workflow_dispatch" ]; then
            if [ "${{ github.event.inputs.module }}" == "${{ matrix.module }}" ]; then
              echo "deploy=true" >> $GITHUB_OUTPUT
            else
              echo "deploy=false" >> $GITHUB_OUTPUT
            fi
          else
            case "${{ matrix.module }}" in
              tf/vault)
                echo "deploy=${{ needs.detect-changes.outputs.vault }}" >> $GITHUB_OUTPUT
                ;;
              tf/grafana)
                echo "deploy=${{ needs.detect-changes.outputs.grafana }}" >> $GITHUB_OUTPUT
                ;;
              tf/authentik)
                echo "deploy=${{ needs.detect-changes.outputs.authentik }}" >> $GITHUB_OUTPUT
                ;;
            esac
          fi

      - name: Trigger Windmill flow
        if: steps.should-deploy.outputs.deploy == 'true'
        env:
          WMILL_TOKEN: ${{ secrets.WMILL_TOKEN }}
        run: |
          echo "Triggering deploy for ${{ matrix.module }} at ${{ github.sha }}"

          response=$(curl -sf -X POST \
            -H "Authorization: Bearer $WMILL_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"module": "${{ matrix.module }}", "ref": "${{ github.sha }}"}' \
            "https://windmill.fzymgc.house/api/w/terraform-gitops-prod/jobs/run/f/terraform/deploy_terraform")

          echo "Windmill job started: $response"
```

**Step 2: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/terraform-deploy.yml'))" && echo "YAML valid"
```

Expected: `YAML valid`

**Step 3: Commit the workflow**

```bash
git add .github/workflows/terraform-deploy.yml
git commit -m "feat(ci): Add terraform-deploy workflow

Triggers Windmill deploy_terraform flow when tf/* modules change.
Supports push to main and manual dispatch.

- Uses dorny/paths-filter for change detection
- Runs on self-hosted runner for Windmill API access
- Matrix strategy handles all three modules

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Delete Old Flow

**Files:**
- Delete: `windmill/f/terraform/deploy_vault.flow/flow.yaml`

**Step 1: Remove the old flow directory**

```bash
rm -rf windmill/f/terraform/deploy_vault.flow
```

**Step 2: Verify deletion**

```bash
ls windmill/f/terraform/deploy_vault.flow 2>&1 | grep -q "No such file" && echo "Deleted successfully"
```

Expected: `Deleted successfully`

**Step 3: Commit the deletion**

```bash
git add -A windmill/f/terraform/deploy_vault.flow
git commit -m "chore(windmill): Remove deploy_vault.flow

Replaced by generic deploy_terraform.flow which accepts module
and ref parameters.

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Update Documentation

**Files:**
- Modify: `docs/windmill-migration.md`

**Step 1: Add note about new workflow**

Add the following section after the "Operational Workflows" section in `docs/windmill-migration.md`:

```markdown
### Terraform GitOps Trigger

The `terraform-deploy.yml` GitHub Actions workflow triggers Windmill flows when Terraform modules change:

- **Trigger:** Push to `main` with changes in `tf/vault/**`, `tf/grafana/**`, or `tf/authentik/**`
- **Manual:** workflow_dispatch with module selector
- **Flow:** `f/terraform/deploy_terraform` (generic parameterized flow)
- **Runner:** `fzymgc-house-cluster-runners` (self-hosted for Windmill API access)
```

**Step 2: Commit documentation update**

```bash
git add docs/windmill-migration.md
git commit -m "docs: Document terraform-deploy workflow

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: Push and Create PR

**Step 1: Push branch**

```bash
git push -u origin feat/terraform-deploy-workflow
```

**Step 2: Create PR**

```bash
gh pr create \
  --title "feat: Add terraform-deploy workflow for GitOps automation" \
  --body "$(cat <<'EOF'
## Summary

Adds GitHub Actions workflow to trigger Windmill flows when Terraform module changes are merged to main.

- Creates generic `deploy_terraform.flow` accepting `module` and `ref` parameters
- Creates `terraform-deploy.yml` workflow with change detection
- Removes module-specific `deploy_vault.flow`

## Changes

- `.github/workflows/terraform-deploy.yml` - New workflow
- `windmill/f/terraform/deploy_terraform.flow/flow.yaml` - New generic flow
- `windmill/f/terraform/deploy_vault.flow/` - Deleted (replaced)
- `docs/windmill-migration.md` - Updated documentation

## Testing

1. Merge this PR
2. Manually trigger workflow via Actions tab to test
3. Make a small tf/vault change to test push trigger

## Design

See `docs/plans/2025-12-14-terraform-deploy-workflow-design.md`

🤖 Generated with [Claude Code](https://claude.ai/code)
EOF
)"
```

---

## Verification Checklist

After PR is merged:

- [ ] Manually trigger workflow from GitHub Actions → should start Windmill job
- [ ] Check Windmill UI for `deploy_terraform` flow execution
- [ ] Verify Discord notification appears (if changes detected)
- [ ] Make small tf/vault change → verify automatic trigger
