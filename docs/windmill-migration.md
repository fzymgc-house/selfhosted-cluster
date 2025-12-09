# Windmill Migration Progress

Migration from Argo Events + Argo Workflows to Windmill for GitOps automation.

**Issue Tracker**: [GitHub Issues #127-#150](https://github.com/fzymgc-house/selfhosted-cluster/issues?q=is%3Aissue+label%3Awindmill-migration)

## Overview

Migrating Terraform GitOps workflows from Argo Events/Workflows to Windmill with:
- GitHub webhooks directly to Windmill
- Flows defined as code in repository
- GitHub Actions with wmill sync for deployment
- Self-hosted GitHub Actions runner (actions-runner-controller)
- Storj S3 for workflow storage
- Windmill approval steps with Discord notifications
- Concurrency control for Terraform applies

## Migration Phases

### Phase 0: Disable Argo Events and Workflows ✅ COMPLETE

**Status**: Completed 2025-12-07

**Issue**: #127

**Completed Tasks**:
- ✅ Disabled automated syncing in ArgoCD applications
  - Modified `argocd/cluster-app/templates/argo-events.yaml`
  - Modified `argocd/cluster-app/templates/argo-workflows.yaml`
- ✅ Merged PR #151 to main branch
- ✅ Synced cluster-app to apply changes
- ✅ Scaled all Argo Events deployments to 0 replicas
- ✅ Scaled all Argo Workflows deployments to 0 replicas

**Verification**:
```bash
# All deployments scaled to zero
kubectl --context fzymgc-house get deployment -n argo-events
kubectl --context fzymgc-house get deployment -n argo-workflows

# No workflow pods running
kubectl --context fzymgc-house get pods -n argo-workflows
```

**Impact**: GitHub webhooks will no longer trigger Terraform workflows. Manual Terraform operations required until Windmill flows are operational.

---

### Phase 1: Set up Infrastructure ✅ COMPLETE

**Status**: Completed 2025-12-07

**Issues**: #128, #129, #130, #131

**Completed Tasks**:
- ✅ Created workspace `terraform-gitops` (#128)
  - Workspace token stored in Vault
  - Workspace synced with `wmill sync`
- ✅ Created actions-runner-controller deployment (#129)
  - ArgoCD app: `argocd/cluster-app/templates/actions-runner-controller.yaml`
  - Runner config: `argocd/app-configs/actions-runner-controller/`
  - GitHub token stored in Vault
  - Documentation: `docs/github-token-setup.md`
- ✅ Configured Storj S3 storage (#130)
  - Resource: `windmill/u/admin/terraform_s3_storage.resource.yaml`
  - Documentation: `docs/windmill-s3-setup.md`
- ✅ Configured Discord bot integration (#131)
  - Resource: `windmill/u/admin/terraform_discord_bot.resource.yaml`
  - Documentation: `docs/windmill-discord-bot-setup.md`
  - Bot credentials stored in Vault

**Workspace Resources Created**:
- `u/admin/github_token` - GitHub repository access
- `u/admin/terraform_discord_bot` - Discord notifications with interactive buttons
- `u/admin/terraform_s3_storage` - S3 backend for Terraform state

**Documentation**:
- `docs/windmill-sync-setup.md` - Complete sync workflow guide
- `docs/github-token-setup.md` - GitHub PAT creation guide
- `docs/windmill-s3-setup.md` - S3 storage configuration
- `docs/windmill-discord-bot-setup.md` - Discord bot setup
- `scripts/setup-windmill-sync.sh` - Automated workspace sync script

---

### Phase 2: Develop Windmill Flows ✅ COMPLETE

**Status**: Completed 2025-12-07

**Issues**: #132, #133, #134, #135, #136

**Completed Tasks**:
- ✅ Created windmill/ directory structure (#132)
  - `wmill.yaml` with Python3 default runtime
  - `variables.json` with all secret definitions
  - `f/terraform/` for flows and scripts
  - `u/admin/` for resources
- ✅ Wrote reusable scripts (#133)
  - `git_clone.py` - Clone repository with GitHub token
  - `terraform_init.py` - Initialize Terraform with S3 backend
  - `terraform_plan.py` - Run plan and parse output
  - `terraform_apply.py` - Apply Terraform changes
  - `notify_approval.py` - Discord approval notifications
  - `notify_status.py` - Discord status notifications
- ✅ Created Terraform deployment flow (#134)
  - `deploy_vault.flow` - Complete flow for tf/vault module
  - Includes: Clone → Init → Plan → Approval → Apply → Notify
  - Skip logic for no-change plans
  - Error handling with failure notifications
- ✅ Configured Windmill resources (#135)
  - Discord bot configuration
  - S3 storage configuration
  - GitHub token configuration
- ✅ Synced to Windmill (#136)
  - All scripts pushed successfully
  - All resources created
  - Flow deployed and ready to test

**Files Created**:
- Scripts: `windmill/f/terraform/*.py` (6 scripts)
- Flow: `windmill/f/terraform/deploy_vault.flow/flow.yaml`
- Resources: `windmill/u/admin/*.resource.yaml` (3 resources)
- Variables: `windmill/variables.json`
- Configuration: `windmill/wmill.yaml`

---

### Phase 3: GitHub Integration ✅ COMPLETE

**Status**: Completed 2025-12-08

**Issues**: #135 (closed - alternative approach), #138 (closed - alternative approach)

**Completed Tasks**:
- ✅ Created GitHub Actions workflows for Windmill sync
  - `windmill-deploy-prod.yaml` - Deploys to production on PR merge
  - `sync-windmill-secrets.yaml` - Syncs secrets from Vault
  - `sync-main-to-windmill-staging.yaml` - Syncs main to staging branch
- ✅ Integrated Vault secret sync into deploy workflow
  - Secrets synced from Vault AFTER code deployment
  - Uses AppRole authentication for secure access

**Note**: Native GitHub webhooks to Windmill were NOT implemented. Instead, GitHub Actions workflows trigger deployments, which provides better control and observability.

---

### Phase 4: Testing ✅ COMPLETE

**Status**: Completed 2025-12-08

**Issues**: #139, #140, #141, #142 (all closed)

**Completed Tasks**:
- ✅ Manual flow execution tests (#139) - Flows operational in staging/prod
- ✅ GitHub Actions trigger tests (#140) - PR merges trigger deployments
- ✅ Concurrency control verification (#141) - Windmill handles concurrency
- ✅ Error handling validation (#142) - Discord notifications working

---

### Phase 5: Cleanup ⏳ PENDING

**Status**: Ready to Start

**Issues**: #143, #144, #145, #146, #147

**Tasks**:
- [ ] Remove Argo Events manifests (#143)
- [ ] Remove Argo Workflows manifests (#144)
- [ ] Clean up Argo secrets (#145)
- [ ] Remove Argo RBAC resources (#146)
- [ ] Update documentation (#147)

**Remaining Files to Remove**:
- `argocd/app-configs/argo-events/` (entire directory)
- `argocd/app-configs/argo-workflows/` (entire directory)
- `argocd/app-configs/authentik-config/gh-repo-sensor.yaml`
- `argocd/app-configs/authentik-config/workflow-template-wf.yaml`
- `argocd/app-configs/grafana-config/gh-repo-sensor.yaml`
- `argocd/app-configs/grafana-config/workflow-template-wf.yaml`
- `argocd/app-configs/vault-config/gh-repo-sensor.yaml`

---

### Phase 6: Monitoring and Optimization ⏳ PENDING

**Status**: Not Started

**Issues**: #148, #149, #150

**Tasks**:
- [ ] Create Grafana dashboards (#148)
- [ ] Implement workflow result caching (#149)
- [ ] Set up alerting (#150)

---

## Current State

### Active Components
- ✅ Windmill (deployed, 3 worker groups, staging + prod workspaces)
- ✅ PostgreSQL (Windmill database)
- ✅ Redis (Windmill cache)
- ✅ GitHub Actions Runner Controller (ARC) with custom image
- ✅ Vault AppRole for CI/CD authentication

### Operational Workflows
- ✅ Vault secret sync from GitHub Actions
- ✅ Windmill code sync via `wmill sync push`
- ✅ Production deployment on PR merge with `windmill` label
- ✅ Discord notifications for approvals and status

### Disabled Components (Ready for Removal)
- ❌ Argo Events (scaled to 0, manifests still present)
- ❌ Argo Workflows (scaled to 0, manifests still present)
- ⚠️ EventBus (still running, will remove in Phase 5)

### Affected Terraform Modules
1. `tf/vault` - Vault policies and configuration
2. `tf/grafana` - Grafana dashboards and data sources
3. `tf/authentik` - Authentik applications and groups

---

## Rollback Plan

Not applicable - per user decision, Argo Events and Workflows are being removed regardless of Windmill migration success.

---

## References

- **Migration Plan**: [GitHub Issues #127-#150](https://github.com/fzymgc-house/selfhosted-cluster/issues?q=is%3Aissue+label%3Awindmill-migration)
- **Windmill Deployment**: `argocd/cluster-app/templates/windmill.yaml`
- **Current Workflows**:
  - `argocd/app-configs/vault-config/vault-config-tf-wf-template-wf.yaml`
  - `argocd/app-configs/grafana-config/workflow-template-wf.yaml`
  - `argocd/app-configs/authentik-config/workflow-template-wf.yaml`

---

**Last Updated**: 2025-12-07

## Phase Completion Summary

- ✅ **Phase 0**: Argo Events/Workflows disabled
- ✅ **Phase 1**: Infrastructure configured (workspace, runner, S3, Discord)
- ✅ **Phase 2**: Windmill flows and scripts developed
- ⏳ **Phase 3**: GitHub Integration (next)
- ⏳ **Phase 4**: Testing
- ⏳ **Phase 5**: Cleanup
- ⏳ **Phase 6**: Monitoring

**Next Steps**: Create GitHub Actions workflow for wmill sync and configure webhooks
