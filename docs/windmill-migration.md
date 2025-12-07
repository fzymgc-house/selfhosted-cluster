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

**Status**: Completed 2025-12-07 (awaiting manual configuration)

**Issues**: #128, #129, #130, #131

**Completed Tasks**:
- ✅ Created workspace setup script and documentation (#128)
  - Script: `scripts/create-windmill-workspace.sh`
  - Manual workspace creation required via UI
- ✅ Created actions-runner-controller deployment (#129)
  - ArgoCD app: `argocd/cluster-app/templates/actions-runner-controller.yaml`
  - Runner config: `argocd/app-configs/actions-runner-controller/`
  - Awaiting GitHub token in Vault
- ✅ Documented Storj S3 configuration (#130)
  - Guide: `docs/windmill-s3-setup.md`
  - Workspace-level S3 resource setup
- ✅ Documented Discord webhook integration (#131)
  - Guide: `docs/windmill-discord-setup.md`
  - Notification script examples

**Manual Steps Required**:
1. Create Windmill workspace `terraform-gitops`
2. Generate and store GitHub Actions token in Vault
3. Create Discord webhook and store in Vault
4. Configure S3 resource in Windmill workspace
5. Configure Discord resource in Windmill workspace

**Documentation**:
- `scripts/create-windmill-workspace.sh`
- `docs/windmill-s3-setup.md`
- `docs/windmill-discord-setup.md`
- `argocd/app-configs/actions-runner-controller/README.md`

---

### Phase 2: Develop Windmill Flows ⏳ PENDING

**Status**: Not Started

**Issues**: #132, #133, #134, #135, #136

**Tasks**:
- [ ] Create windmill/ directory structure (#132)
- [ ] Write reusable scripts (#133)
- [ ] Create Terraform deployment flow (#134)
- [ ] Configure Windmill resources (#135)
- [ ] Test flows locally (#136)

---

### Phase 3: GitHub Integration ⏳ PENDING

**Status**: Not Started

**Issues**: #137, #138

**Tasks**:
- [ ] Create GitHub Actions workflow for wmill sync (#137)
- [ ] Configure GitHub webhooks to Windmill (#138)

---

### Phase 4: Testing ⏳ PENDING

**Status**: Not Started

**Issues**: #139, #140, #141, #142

**Tasks**:
- [ ] Manual flow execution tests (#139)
- [ ] GitHub webhook trigger tests (#140)
- [ ] Concurrency control verification (#141)
- [ ] Error handling validation (#142)

---

### Phase 5: Cleanup ⏳ PENDING

**Status**: Not Started

**Issues**: #143, #144, #145, #146, #147

**Tasks**:
- [ ] Remove Argo Events manifests (#143)
- [ ] Remove Argo Workflows manifests (#144)
- [ ] Clean up Argo secrets (#145)
- [ ] Remove Argo RBAC resources (#146)
- [ ] Update documentation (#147)

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
- ✅ Windmill (deployed, 3 worker groups)
- ✅ PostgreSQL (Windmill database)
- ✅ Redis (Windmill cache)

### Disabled Components
- ❌ Argo Events (scaled to 0)
- ❌ Argo Workflows (scaled to 0)
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
