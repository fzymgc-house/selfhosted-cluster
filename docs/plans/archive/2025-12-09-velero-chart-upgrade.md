# Velero Chart Upgrade Design

**Date**: 2025-12-09
**Author**: Claude Code + Sean
**Status**: Approved

## Overview and Goals

### Objective
Migrate Velero from chart version 10.1.2 to 11.2.0 and eliminate all Bitnami dependencies using a two-phase approach to minimize risk.

### Current State
- **Chart**: vmware-tanzu/velero 10.1.2 (Velero 1.16.2)
- **Kubectl image override**: `bitnamilegacy/kubectl:1.33.4` (manually added to fix ImagePullBackOff)
- **Deployment**: ArgoCD-managed with auto-sync enabled
- **Backup storage**: Cloudflare R2 (S3-compatible)
- **Node agents**: Running on 4 control-plane nodes

### Target State
- **Chart**: vmware-tanzu/velero 11.2.0 (Velero 1.17.1)
- **Kubectl image**: `cgr.dev/chainguard/kubectl:latest-dev` (actively maintained, security-focused)
- **All Bitnami dependencies removed**
- **Backward compatibility maintained** (existing backups remain accessible)

### Constraints
- Must follow GitOps workflow (no manual kubectl apply)
- Must maintain backup continuity (no downtime for backup operations)
- Must validate existing backups before proceeding
- Changes must be reversible via ArgoCD

### Success Criteria
- ArgoCD syncs successfully to new chart version
- All Velero pods healthy and running
- Existing backups remain accessible and restorable
- New backups complete successfully
- Scheduled backups continue on schedule
- Metrics/monitoring functional

## Phase 1: Chart Upgrade (10.1.2 → 11.2.0)

### Breaking Changes Analysis
Analysis shows **no breaking changes** between versions:
- Velero 1.16.2 → 1.17.1 (backward compatible)
- AWS plugin 1.12.2 → 1.13.1 (compatible)
- Monitoring improvements (ServiceMonitor → PodMonitor for node-agent)
- Better alert thresholds (30h → 25h for backup failures)
- Config restructuring (`latestJobsCount` → `global.keepLatestMaintenanceJobs`)

All changes are additive/improvements with no deprecated fields in current config.

### Pre-Upgrade Documentation
Before making any changes, capture current state:

1. **List existing backups**:
   ```bash
   kubectl --context fzymgc-house get backup -n velero
   ```

2. **Verify latest backup accessible**:
   ```bash
   velero backup describe <latest-backup>
   ```

3. **Document current chart values**: Already in git at `argocd/cluster-app/templates/velero.yaml`

4. **Tag current working state**:
   ```bash
   git tag velero-10.1.2-working
   git push origin velero-10.1.2-working
   ```

### Configuration Changes

Update `argocd/cluster-app/templates/velero.yaml`:

```yaml
# Line 13: Update chart version
targetRevision: 11.2.0  # was: 10.1.2

# Line 20: Update Velero app version
image:
    repository: velero/velero
    tag: v1.17.1  # was: v1.16.2

# Line 42: Update AWS plugin version
initContainers:
    - name: velero-plugin-for-aws
      image: velero/velero-plugin-for-aws:v1.13.1  # was: v1.12.2

# Lines 80-83: Keep existing kubectl override for Phase 1
kubectl:
    image:
        repository: bitnamilegacy/kubectl
        tag: "1.33.4"
```

### Deployment Process

1. **Commit changes** to `feat/velero-chart-upgrade` branch
2. **Create PR** with upgrade details and reference to this design doc
3. **After PR approval and merge to main**:
   - ArgoCD auto-sync triggers (within 3 minutes)
   - ArgoCD runs upgrade-crds hook job (with bitnamilegacy kubectl)
   - Velero deployment rolls out new version
4. **Monitor sync**: `kubectl get application velero -n argocd -w`

### Expected Behavior
- Velero pods perform rolling restart
- Node agent pods restart (one per node, 4 total)
- Existing backups remain untouched and accessible
- Scheduled backups continue running (no interruption)

### Validation (Standard Level)

#### 1. Immediate Health Checks (within 5 minutes)
```bash
# ArgoCD sync status
kubectl get application velero -n argocd

# Pod health - expect 5 pods running (1 velero + 4 node-agents)
kubectl get pods -n velero

# Review logs for errors
kubectl logs -n velero deployment/velero --tail=50
```

#### 2. Backup Accessibility (within 15 minutes)
```bash
# List existing backups
velero backup get

# Verify latest backup details
velero backup describe <latest-backup-name>

# Confirm backup storage location accessible
velero backup-location get
```

#### 3. Functional Testing (within 1 hour)
```bash
# Create test backup
velero backup create test-upgrade-backup --include-namespaces=<test-namespace>

# Wait for completion
velero backup describe test-upgrade-backup

# Test restore to validate
velero restore create --from-backup test-upgrade-backup
```

#### 4. Scheduled Backup Verification (within 24 hours)
```bash
# Verify scheduled backups run
velero schedule get

# Check next scheduled backup completes successfully
# Review backup metrics in Grafana/Prometheus
```

#### 5. Monitoring Validation
- Verify ServiceMonitor/PodMonitor working
- Check Prometheus scraping Velero metrics
- Confirm no alerts firing

## Phase 2: Kubectl Image Migration (Chainguard)

### Timing
Execute Phase 2 only after Phase 1 is stable and validated:
- Typically 24-48 hours after Phase 1
- After several successful scheduled backups
- When all Phase 1 validation checks pass

### Why Chainguard kubectl
- **Security-focused**: Minimal attack surface, regularly patched
- **Actively maintained**: Not deprecated like Bitnami
- **Community validated**: Confirmed working in vmware-tanzu/helm-charts#698
- **Has required tools**: `:latest-dev` variant includes shell and kubectl binary for upgrade-crds hook
- **Free for latest tag**: No subscription required for `:latest-dev`

### Configuration Change

Update `argocd/cluster-app/templates/velero.yaml`:

```yaml
# Lines 80-83: Change kubectl image
kubectl:
    image:
        repository: cgr.dev/chainguard/kubectl  # was: bitnamilegacy/kubectl
        tag: "latest-dev"  # was: "1.33.4"
```

### Deployment Process
1. **Commit** kubectl image change to feature branch
2. **Create separate PR** titled "Phase 2: Migrate kubectl to Chainguard"
3. **After merge**, ArgoCD triggers another sync
4. **upgrade-crds hook job** runs with new Chainguard image
5. **Main Velero pods unaffected** (only hook jobs use kubectl image)

### Validation
- Verify upgrade-crds job completes successfully with Chainguard image
- Run test backup: `velero backup create test-chainguard-kubectl`
- Check ArgoCD application shows Healthy status

## Rollback Strategy

### Pre-Rollback Preparation
- Git tag created before Phase 1: `velero-10.1.2-working`
- Current working config preserved in git history
- All changes declarative in ArgoCD application manifest

### Phase 1 Rollback (If chart 11.2.0 has issues)

**Method**: ArgoCD-based rollback to maintain GitOps workflow

#### Option 1: Immediate Git Revert
```bash
# Revert the commit in git
git revert <upgrade-commit-hash>
git push origin main

# ArgoCD auto-syncs back to 10.1.2 within 3 minutes
# Or force immediate sync:
kubectl patch application velero -n argocd \
  -p '{"operation":{"initiatedBy":{"username":"rollback"},"sync":{}}}' --type merge
```

#### Option 2: Manual ArgoCD Rollback
```bash
# Use ArgoCD to sync to previous revision
argocd app rollback velero <previous-revision-id>
```

#### Verify Rollback
```bash
# Confirm pods running old version
kubectl get pods -n velero -o yaml | grep "image:"

# Verify backups still accessible
velero backup get

# Check scheduled backups continue
velero schedule get
```

### Phase 2 Rollback (If Chainguard kubectl fails)
- Same process as Phase 1 rollback
- Revert kubectl image change commit
- ArgoCD syncs back to `bitnamilegacy/kubectl:1.33.4`
- Lower risk since only affects upgrade-crds hook job

### Rollback Decision Criteria

Trigger rollback if:
- Velero pods crash-looping
- Existing backups become inaccessible
- New backups fail consistently
- Critical errors in Velero logs
- ArgoCD sync fails repeatedly

## Implementation Timeline

1. **Pre-work**: Document current state and create git tag (~10 minutes)
2. **Phase 1 Implementation**: Update chart version, create PR, merge (~30 minutes)
3. **Phase 1 Validation**: Run standard validation checks (~1-2 hours)
4. **Stabilization Period**: Monitor for 24-48 hours
5. **Phase 2 Implementation**: Update kubectl image, create PR, merge (~15 minutes)
6. **Phase 2 Validation**: Quick health checks (~15 minutes)
7. **Final Verification**: Confirm no Bitnami dependencies remain (~5 minutes)

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Chart upgrade breaks backups | Low | High | No breaking changes identified; rollback ready |
| Existing backups inaccessible | Very Low | High | Backward compatible; pre-validation required |
| Chainguard kubectl incompatible | Low | Low | Community validated; only affects hook jobs |
| ArgoCD sync failure | Very Low | Medium | Rollback via git revert |
| Scheduled backup interruption | Very Low | Medium | Rolling restart maintains continuity |

## Success Metrics

### Phase 1
- [ ] ArgoCD sync completed successfully
- [ ] All 5 Velero pods running (1 controller + 4 node-agents)
- [ ] All existing backups accessible
- [ ] New test backup created and restorable
- [ ] Scheduled backups continue on schedule
- [ ] Metrics/monitoring functional
- [ ] No errors in Velero logs

### Phase 2
- [ ] upgrade-crds hook job completes with Chainguard image
- [ ] Test backup succeeds with new kubectl image
- [ ] ArgoCD application healthy
- [ ] No Bitnami dependencies in configuration

## References

- VMware Tanzu Velero chart: https://github.com/vmware-tanzu/helm-charts
- Chart 11.2.0 release: https://github.com/vmware-tanzu/helm-charts/releases/tag/velero-11.2.0
- Bitnami kubectl deprecation: https://github.com/bitnami/charts/issues/35164
- Kubectl image discussion: https://github.com/vmware-tanzu/helm-charts/issues/698
- Chainguard kubectl: https://edu.chainguard.dev/chainguard/chainguard-images/reference/kubectl/
