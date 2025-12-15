# Velero Upgrade Project - Status Report

**Date**: 2025-12-09
**Status**: Phase 1 Complete, Stabilization In Progress
**Next**: Phase 2 (kubectl image migration)

## Executive Summary

**Phase 1 is complete and deployed.** Velero has been successfully upgraded from chart 10.1.2 to 11.2.0 (Velero 1.16.2 → 1.17.1). The system is currently in a 24-48 hour stabilization period to ensure reliability before proceeding with Phase 2, which will migrate the kubectl image from Bitnami to Chainguard.

**Current State**: All 5 Velero pods running (1 controller + 4 node-agents), scheduled backups active, no errors observed.

**Timeline**:
- Phase 1 deployed: 2025-12-09 ~19:49 UTC (PR #242 merged)
- Stabilization period: 24-48 hours (target completion: 2025-12-11)
- Phase 2 ready: After stabilization confirms health

## Phase 1 Completed (Tasks 1-4)

### What Was Done

**PR #242**: "feat(velero): Phase 1 - Upgrade chart to 11.2.0"
- Merged: 2025-12-09 19:49:17Z
- Branch: `feat/velero-chart-upgrade`

**Changes Applied**:
1. Chart version: 10.1.2 → 11.2.0
2. Velero application: v1.16.2 → v1.17.1
3. AWS plugin: v1.12.2 → v1.13.1
4. kubectl image: Kept `bitnamilegacy/kubectl:1.33.4` (Phase 2 will migrate)

**Pre-Upgrade Actions**:
- Git tag created: `velero-10.1.2-working` (rollback reference)
- Existing backups verified accessible
- Backup storage location confirmed healthy
- Pre-upgrade documentation: `docs/plans/2025-12-09-pre-upgrade-verification.md`

### Validation Results

**Deployment Status** (as of 2025-12-09 ~20:00 UTC):
```
Velero controller: 1/1 Running (10 minutes uptime)
Node agents: 4/4 Running (9-10 minutes uptime)
Image: velero/velero:v1.17.1 ✓
ArgoCD sync: Healthy ✓
```

**Backup System Health**:
- Backup storage location: Available, ReadWrite access ✓
- Scheduled backups: Both enabled and running
  - `daily-backup`: Last ran 18h ago (successful)
  - `weekly-full-backup`: Last ran 2d ago (successful)
- Existing backups: Accessible (retention policy auto-cleanup active)

**No Issues Detected**:
- Zero pod restarts since deployment
- No errors in Velero controller logs
- ArgoCD application status: Synced and Healthy
- No alerts firing

## Current System State

### Deployed Versions

| Component | Version | Status |
|-----------|---------|--------|
| Helm Chart | 11.2.0 | Deployed |
| Velero | v1.17.1 | Running |
| AWS Plugin | v1.13.1 | Running |
| kubectl (hook) | bitnamilegacy/kubectl:1.33.4 | In config (Phase 2 pending) |

### Pod Health

```
NAME                        READY   STATUS    AGE
velero-6cf9967797-zxxtr    1/1     Running   10m
node-agent-l2fsh           1/1     Running   10m
node-agent-msw8m           1/1     Running   10m
node-agent-pxngl           1/1     Running   10m
node-agent-x8pxb           1/1     Running   9m
```

All pods healthy with no restarts.

### Backup Schedules

| Schedule | Status | Last Backup | Next Due | Retention |
|----------|--------|-------------|----------|-----------|
| daily-backup | Enabled | 18h ago | ~6h (02:00 UTC) | 30 days |
| weekly-full-backup | Enabled | 2d ago | ~5d (Sunday 03:00 UTC) | 90 days |

### Storage Backend

- **Provider**: Cloudflare R2 (S3-compatible)
- **Location**: `fzymgc-cluster-storage/velero/backups`
- **Status**: Available
- **Access Mode**: ReadWrite
- **Last Validated**: 2025-12-09 ~19:32 EST

## Current Phase: Stabilization (Task 5)

### Why We're Waiting

The 24-48 hour stabilization period serves critical purposes:

1. **Validate Production Workload**: Ensure upgraded Velero handles real scheduled backups (not just test backups)
2. **Detect Latent Issues**: Some problems only appear after multiple backup cycles
3. **Verify Resource Stability**: Confirm no memory leaks, pod restarts, or performance degradation
4. **Build Confidence**: Prove system stability before making additional changes

This is **standard practice** for backup system upgrades - we don't rush changes to the component that protects all other data.

### What to Monitor

**Daily Checks** (run once per day during stabilization):

```bash
# 1. Check pod health (expect no restarts)
kubectl --context fzymgc-house get pods -n velero

# 2. Verify scheduled backups completing
velero schedule get
velero backup get --schedule=daily-backup

# 3. Check for errors in controller logs
kubectl --context fzymgc-house logs -n velero deployment/velero --tail=100 | grep -i error

# 4. Verify backup storage location
velero backup-location get

# 5. Check ArgoCD application health
kubectl --context fzymgc-house get application velero -n argocd
```

**What You Should See**:
- All 5 pods Running with 0 restarts
- New backup created daily at 02:00 UTC
- Backup status: Phase: Completed
- No ERROR or FATAL in logs
- Backup location: Available
- ArgoCD: Synced and Healthy

**Red Flags** (trigger investigation):
- Pod restarts or crash loops
- Backup failures (Phase: Failed)
- Errors in Velero logs
- Backup location becomes Unavailable
- ArgoCD shows Degraded

### Success Criteria

Proceed to Phase 2 only when **ALL** criteria met:

- [ ] **Time elapsed**: At least 24 hours, ideally 48 hours
- [ ] **Scheduled backups**: At least 2 daily backups completed successfully (check at 02:00 UTC + 1h)
- [ ] **Pod stability**: Zero unexpected restarts across all 5 pods
- [ ] **No errors**: Clean logs with no ERROR/FATAL messages
- [ ] **No alerts**: Grafana shows no Velero-related alerts firing
- [ ] **Storage healthy**: Backup location remains Available

**Next Scheduled Backup**: Tomorrow (2025-12-10) at 02:00 UTC
- Check status after 03:00 UTC
- Should see new backup in `velero backup get --schedule=daily-backup`

### Timeline

- **Started**: 2025-12-09 ~19:49 UTC (PR #242 merge)
- **Check 1**: 2025-12-10 03:00 UTC (after first scheduled backup)
- **Check 2**: 2025-12-11 03:00 UTC (after second scheduled backup)
- **Ready for Phase 2**: 2025-12-11 ~04:00 UTC (earliest, if all green)

## Next: Phase 2 (Tasks 6-9)

### What Will Change

**Single configuration change** in `argocd/cluster-app/templates/velero.yaml`:

```yaml
# Current (Phase 1):
kubectl:
    image:
        repository: bitnamilegacy/kubectl
        tag: "1.33.4"

# After Phase 2:
kubectl:
    image:
        repository: cgr.dev/chainguard/kubectl
        tag: "latest-dev"
```

**Impact**:
- Only affects `upgrade-crds` pre-upgrade hook job
- Main Velero controller and node-agent pods **unchanged**
- Very low risk (kubectl image only used during Helm upgrades)

### Why Chainguard

- **Security-focused**: Minimal attack surface, regularly patched
- **Actively maintained**: Bitnami kubectl is deprecated
- **Community validated**: Confirmed working in vmware-tanzu/helm-charts#698
- **Has required tools**: `:latest-dev` includes shell and kubectl for hook execution
- **Free**: No subscription required for `:latest-dev` tag

### When to Start Phase 2

**Earliest**: 2025-12-11 after stabilization period

**Prerequisites** (verify before starting):
1. At least 48 hours since Phase 1 deployment
2. At least 2 successful daily scheduled backups (2025-12-10, 2025-12-11)
3. All 5 pods Running with 0 restarts
4. Clean logs with no errors
5. No Grafana alerts firing
6. Backup storage location healthy

### Expected Process

1. **Update configuration**: Change kubectl image in `velero.yaml` (lines 80-83)
2. **Create PR**: "feat(velero): Phase 2 - Migrate kubectl to Chainguard"
3. **Merge to main**: ArgoCD auto-syncs changes
4. **Validation**: Quick health checks (15 minutes)
   - ArgoCD sync successful
   - Pods unchanged (kubectl only affects future upgrade hooks)
   - Test backup completes successfully
5. **Completion**: All Bitnami dependencies eliminated

**Risk Level**: Very Low
- Change only affects pre-upgrade hook jobs (not running now)
- Will be used during *next* Helm upgrade (not this one)
- Main Velero functionality completely unaffected
- Rollback is simple: revert commit, ArgoCD syncs back

## Monitoring Checklist

### Daily During Stabilization

Copy and paste this checklist for daily checks:

```markdown
## Date: ____-__-__

### Pod Health
- [ ] All 5 pods Running
- [ ] Zero restarts since last check
- [ ] velero controller: Running
- [ ] node-agent x4: All Running

### Backup Status
- [ ] Backup location: Available
- [ ] Daily backup ran: [ ] Yes [ ] No
- [ ] Latest backup Phase: Completed
- [ ] No backup failures

### System Health
- [ ] ArgoCD: Synced and Healthy
- [ ] No errors in velero logs (last 100 lines)
- [ ] No Grafana alerts firing
- [ ] Scheduled backups on time

### Notes
[Any observations or concerns]
```

### Commands Reference

Quick access during stabilization:

```bash
# Pod status
kubectl --context fzymgc-house get pods -n velero

# Recent backups
velero backup get | head -n 10

# Backup schedules
velero schedule get

# Check for errors
kubectl --context fzymgc-house logs -n velero deployment/velero --tail=100 | grep -E '(ERROR|FATAL|error|failed)'

# Storage location
velero backup-location get

# ArgoCD status
kubectl --context fzymgc-house get application velero -n argocd -o jsonpath='{.status.sync.status} {.status.health.status}'
```

## Rollback Plan

### If Issues Found During Stabilization

**Symptoms requiring rollback**:
- Backup failures (Phase: Failed or PartiallyFailed)
- Pod crash loops or frequent restarts
- Backup storage location becomes Unavailable
- Critical errors in Velero logs
- Data restore failures

**Rollback Process**:

```bash
# 1. Identify the Phase 1 upgrade commit
git log --oneline -10 | grep "velero"
# Look for: b75d7c8 feat(velero): Phase 1 - Upgrade chart to 11.2.0 (#242)

# 2. Revert the commit on main
git checkout main
git pull
git revert b75d7c8
git push origin main

# 3. ArgoCD auto-syncs within 3 minutes (or force sync)
kubectl --context fzymgc-house get application velero -n argocd -w

# 4. Verify rollback complete
kubectl --context fzymgc-house get deployment velero -n velero -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: velero/velero:v1.16.2

# 5. Verify backups accessible
velero backup get
velero backup describe <latest-backup>

# 6. Document what happened
# Create: docs/plans/2025-12-09-phase1-rollback.md
```

**Alternative**: Use git tag for immediate rollback:
```bash
git reset --hard velero-10.1.2-working
git push origin main --force  # CAUTION: Only if sole developer
```

### If Issues Found During Phase 2

Phase 2 rollback is simpler (lower risk):

```bash
# Revert Phase 2 commit
git revert <phase2-commit-hash>
git push origin main

# ArgoCD syncs kubectl image back to bitnamilegacy
# Main Velero pods unaffected
```

## References

### Design Documents

- **Design**: `docs/plans/2025-12-09-velero-chart-upgrade.md`
- **Implementation Plan**: `docs/plans/2025-12-09-velero-chart-upgrade-implementation.md`
- **Pre-Upgrade Verification**: `docs/plans/2025-12-09-pre-upgrade-verification.md`

### Pull Requests

- **Phase 1**: PR #242 - "feat(velero): Phase 1 - Upgrade chart to 11.2.0"
  - Merged: 2025-12-09 19:49:17Z
  - Status: Complete

### Git Tags

- `velero-10.1.2-working`: Pre-upgrade snapshot (rollback reference)
- `velero-11.2.0-complete`: Will be created after Phase 2

### Upstream References

- [Velero Chart 11.2.0 Release](https://github.com/vmware-tanzu/helm-charts/releases/tag/velero-11.2.0)
- [Velero 1.17.1 Release Notes](https://github.com/vmware-tanzu/velero/releases/tag/v1.17.1)
- [Bitnami kubectl Deprecation](https://github.com/bitnami/charts/issues/35164)
- [Chainguard kubectl Discussion](https://github.com/vmware-tanzu/helm-charts/issues/698)
- [Chainguard kubectl Docs](https://edu.chainguard.dev/chainguard/chainguard-images/reference/kubectl/)

### Monitoring Dashboards

- **Grafana**: https://grafana.fzymgc.house (search for "Velero")
- **ArgoCD**: https://argocd.fzymgc.house/applications/velero
- **Traefik**: https://traefik.fzymgc.house

## Validation Results Summary

### Phase 1 Validation (2025-12-09 ~20:00 UTC)

**Immediate Health Checks**: ✓ All Passed
- ArgoCD sync: Successful
- Pods: 5/5 Running
- Velero version: v1.17.1 (correct)
- Logs: Clean, no errors

**Backup Validation**: ✓ All Passed
- Existing backups: Accessible
- Backup location: Available (ReadWrite)
- Scheduled backups: Enabled and on schedule

**Monitoring**: ✓ All Passed
- ServiceMonitor/PodMonitor: Present
- No alerts firing
- Metrics scraping: Active

**Outstanding**:
- [ ] Production scheduled backup validation (in progress during stabilization)
- [ ] 24-48 hour stability confirmation (in progress)

### Phase 2 Validation (Pending)

Will include:
- ArgoCD sync with Chainguard config
- Test backup with new configuration
- Verification no Bitnami dependencies remain

## Decision Gate: Proceed to Phase 2?

**Check this section on 2025-12-11 after 03:00 UTC:**

```markdown
## Phase 2 Readiness Assessment - [DATE]

### Time Criteria
- [ ] 48+ hours elapsed since Phase 1 (deployed 2025-12-09 19:49 UTC)

### Scheduled Backup Validation
- [ ] 2025-12-10 02:00 UTC backup: [ ] Success [ ] Failed [ ] Not checked
- [ ] 2025-12-11 02:00 UTC backup: [ ] Success [ ] Failed [ ] Not checked

### System Health
- [ ] All pods Running with 0 restarts
- [ ] No errors in logs (checked last 100 lines)
- [ ] Backup location: Available
- [ ] No Grafana alerts firing

### Decision
- [ ] **PROCEED to Phase 2** - All criteria met
- [ ] **DELAY Phase 2** - Reason: ___________________________
- [ ] **ROLLBACK Phase 1** - Issue: ___________________________

### Notes
[Document any concerns or observations]
```

## Summary

**Current State**: Phase 1 deployed successfully, system healthy, stabilization in progress.

**Action Required**: Monitor daily during stabilization period (2025-12-09 through 2025-12-11).

**Next Step**: Proceed to Phase 2 (kubectl image migration) after stabilization criteria met (~2025-12-11).

**Risk Level**: Low - Phase 1 stable, Phase 2 is minimal change with very low impact.

---

**Document Status**: Living document - update with daily monitoring results during stabilization.
