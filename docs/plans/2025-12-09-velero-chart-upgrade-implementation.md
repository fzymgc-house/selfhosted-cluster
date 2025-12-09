# Velero Chart Upgrade Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Upgrade Velero from chart 10.1.2 to 11.2.0 and migrate from Bitnami kubectl to Chainguard kubectl in two phases.

**Architecture:** Two-phase GitOps upgrade via ArgoCD. Phase 1 updates chart version while keeping Bitnami kubectl for safety. Phase 2 migrates to Chainguard kubectl after validation. Both phases follow PR workflow with standard validation.

**Tech Stack:** Kubernetes, ArgoCD, Helm, Velero, Cloudflare R2, Chainguard images

---

## Task 1: Pre-Upgrade Documentation

**Files:**
- Read: `argocd/cluster-app/templates/velero.yaml` (current config)
- Document: Terminal output (not saved to files)

**Step 1: List all existing backups**

Run:
```bash
kubectl --context fzymgc-house get backup -n velero -o wide
```

Expected: List of backups with STATUS, AGE, and EXPIRATION
Copy output to clipboard or take screenshot for reference.

**Step 2: Verify latest backup is accessible**

Run:
```bash
# Get the latest backup name from previous step
velero backup describe <latest-backup-name>
```

Expected: Detailed backup information showing Phase: Completed, Status: []
Note backup name and completion time.

**Step 3: Check current Velero version**

Run:
```bash
kubectl --context fzymgc-house get deployment velero -n velero -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Expected: `velero/velero:v1.16.2`

**Step 4: Verify backup storage location**

Run:
```bash
velero backup-location get
```

Expected: NAME: default, PROVIDER: velero.io/aws, ACCESS MODE: ReadWrite, AVAILABLE: true

**Step 5: Create git tag for rollback reference**

Run:
```bash
git tag velero-10.1.2-working
git push origin velero-10.1.2-working
```

Expected: Tag created and pushed successfully

**Step 6: Commit documentation**

Run:
```bash
git commit --allow-empty -m "chore: Pre-upgrade documentation checkpoint

Verified Velero 1.16.2 with chart 10.1.2:
- Backups accessible and healthy
- Backup storage location available
- Git tag created for rollback: velero-10.1.2-working

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Expected: Empty commit created as checkpoint

---

## Task 2: Phase 1 - Update Chart Configuration

**Files:**
- Modify: `argocd/cluster-app/templates/velero.yaml:13,20,42`

**Step 1: Update chart version**

File: `argocd/cluster-app/templates/velero.yaml`

Change line 13:
```yaml
# Before:
          targetRevision: 10.1.2

# After:
          targetRevision: 11.2.0
```

**Step 2: Update Velero app version**

Same file, change line 20:
```yaml
# Before:
                  image:
                      repository: velero/velero
                      tag: v1.16.2

# After:
                  image:
                      repository: velero/velero
                      tag: v1.17.1
```

**Step 3: Update AWS plugin version**

Same file, change line 42:
```yaml
# Before:
                  initContainers:
                      - name: velero-plugin-for-aws
                        image: velero/velero-plugin-for-aws:v1.12.2

# After:
                  initContainers:
                      - name: velero-plugin-for-aws
                        image: velero/velero-plugin-for-aws:v1.13.1
```

**Step 4: Verify kubectl image override is present**

Same file, verify lines 80-83 exist:
```yaml
                  kubectl:
                      image:
                          repository: bitnamilegacy/kubectl
                          tag: "1.33.4"
```

Expected: Lines present (keep for Phase 1)

**Step 5: Validate YAML syntax**

Run:
```bash
yamllint argocd/cluster-app/templates/velero.yaml
```

Expected: No errors

**Step 6: Commit Phase 1 changes**

Run:
```bash
git add argocd/cluster-app/templates/velero.yaml
git commit -m "feat(velero): Upgrade chart to 11.2.0 (Velero 1.17.1)

Phase 1 of 2-phase upgrade:
- Chart: 10.1.2 → 11.2.0
- Velero: 1.16.2 → 1.17.1
- AWS plugin: 1.12.2 → 1.13.1
- Keep bitnamilegacy/kubectl:1.33.4 for safety

See docs/plans/2025-12-09-velero-chart-upgrade.md for full plan.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Expected: Commit created with changes

---

## Task 3: Phase 1 - Create Pull Request

**Files:**
- None (GitHub operations)

**Step 1: Push feature branch**

Run:
```bash
git push -u origin feat/velero-chart-upgrade
```

Expected: Branch pushed to origin

**Step 2: Create pull request**

Run:
```bash
gh pr create --title "feat(velero): Phase 1 - Upgrade chart to 11.2.0" --body "$(cat <<'EOF'
## Phase 1: Velero Chart Upgrade

Upgrades Velero from chart 10.1.2 to 11.2.0 (Velero 1.16.2 → 1.17.1).

### Changes
- Chart version: 10.1.2 → 11.2.0
- Velero app: 1.16.2 → 1.17.1
- AWS plugin: 1.12.2 → 1.13.1
- Keeps bitnamilegacy/kubectl:1.33.4 (Phase 2 will migrate to Chainguard)

### Pre-Upgrade Verification
- [x] Existing backups verified accessible
- [x] Backup storage location healthy
- [x] Git tag created: velero-10.1.2-working

### Breaking Changes Analysis
No breaking changes identified:
- Backward compatible Velero version bump
- AWS plugin compatible
- Config changes are additive/improvements only

### Validation Plan
After merge, validate:
- [ ] ArgoCD syncs successfully
- [ ] All 5 pods running (1 controller + 4 node-agents)
- [ ] Existing backups still accessible
- [ ] New test backup succeeds
- [ ] Scheduled backups continue

### Rollback Plan
If issues occur:
\`\`\`bash
# Revert commit and ArgoCD auto-syncs back
git revert HEAD
git push origin main

# Or use git tag
git reset --hard velero-10.1.2-working
\`\`\`

### References
- Design doc: docs/plans/2025-12-09-velero-chart-upgrade.md
- Chart release: https://github.com/vmware-tanzu/helm-charts/releases/tag/velero-11.2.0

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR created with URL returned

**Step 3: Note PR number**

Copy PR URL for reference in validation steps.

---

## Task 4: Phase 1 - Post-Merge Validation (Standard Level)

**Prerequisites:** PR merged to main, ArgoCD sync triggered

**Files:**
- None (read-only validation)

**Step 1: Wait for ArgoCD sync to start**

Run:
```bash
# Wait up to 3 minutes for auto-sync
sleep 180
kubectl --context fzymgc-house get application velero -n argocd -o jsonpath='{.status.operationState.phase}'
```

Expected: "Running" or "Succeeded"

**Step 2: Monitor sync to completion**

Run:
```bash
kubectl --context fzymgc-house get application velero -n argocd -w
```

Expected: STATUS: Synced, HEALTH: Healthy
Press Ctrl+C when Healthy.

**Step 3: Verify pod health**

Run:
```bash
kubectl --context fzymgc-house get pods -n velero
```

Expected: 5 pods total, all STATUS: Running, READY: 1/1
- 1 velero pod (controller)
- 4 node-agent pods

**Step 4: Verify Velero version**

Run:
```bash
kubectl --context fzymgc-house get deployment velero -n velero -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Expected: `velero/velero:v1.17.1`

**Step 5: Check Velero logs for errors**

Run:
```bash
kubectl --context fzymgc-house logs -n velero deployment/velero --tail=50
```

Expected: No ERROR or FATAL messages, should see "Successfully initialized" messages

**Step 6: List existing backups**

Run:
```bash
velero backup get
```

Expected: Same backups as pre-upgrade, all with Phase: Completed

**Step 7: Describe latest backup**

Run:
```bash
velero backup describe <latest-backup-name>
```

Expected: Phase: Completed, no errors in Status field

**Step 8: Verify backup storage location**

Run:
```bash
velero backup-location get
```

Expected: AVAILABLE: true, ACCESS MODE: ReadWrite

**Step 9: Create test backup**

Run:
```bash
# Pick a small test namespace (not critical)
velero backup create test-phase1-upgrade --include-namespaces=<test-namespace> --wait
```

Expected: Backup completed successfully after 1-3 minutes

**Step 10: Verify test backup details**

Run:
```bash
velero backup describe test-phase1-upgrade
```

Expected: Phase: Completed, Status: []

**Step 11: Test restore from test backup**

Run:
```bash
velero restore create test-phase1-restore --from-backup test-phase1-upgrade --wait
```

Expected: Restore completed successfully

**Step 12: Verify scheduled backups**

Run:
```bash
velero schedule get
```

Expected: All schedules present with LAST BACKUP showing recent timestamps

**Step 13: Check Prometheus metrics**

Run:
```bash
kubectl --context fzymgc-house get servicemonitor -n velero
kubectl --context fzymgc-house get podmonitor -n velero
```

Expected: ServiceMonitor and PodMonitor resources present

**Step 14: Verify no ArgoCD sync errors**

Run:
```bash
kubectl --context fzymgc-house get application velero -n argocd -o jsonpath='{.status.conditions}'
```

Expected: Empty array [] or no error conditions

**Step 15: Document Phase 1 completion**

Create file: `docs/plans/2025-12-09-phase1-validation-results.md`

Content:
```markdown
# Phase 1 Validation Results

**Date:** $(date +%Y-%m-%d)
**Chart Version:** 11.2.0
**Velero Version:** 1.17.1

## Health Checks ✓
- ArgoCD sync: Successful
- Pods running: 5/5 (1 controller + 4 node-agents)
- Velero logs: No errors

## Backup Validation ✓
- Existing backups: Accessible
- Test backup: Created successfully
- Test restore: Completed successfully
- Backup storage: Available

## Monitoring ✓
- ServiceMonitor: Present
- PodMonitor: Present
- Scheduled backups: Running

## Next Steps
- Monitor for 24-48 hours
- Verify next scheduled backup completes
- Proceed to Phase 2 after stabilization
```

Run:
```bash
git add docs/plans/2025-12-09-phase1-validation-results.md
git commit -m "docs: Phase 1 validation results

All validation checks passed:
- ArgoCD sync successful
- All pods healthy
- Backups accessible and working
- Test backup/restore successful

Ready for Phase 2 after stabilization period.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
git push origin feat/velero-chart-upgrade
```

Expected: Validation results documented

---

## Task 5: Phase 1 Stabilization Period

**Prerequisites:** Phase 1 validation passed

**Files:**
- None (monitoring only)

**Step 1: Wait 24-48 hours**

Monitor during stabilization:
```bash
# Check scheduled backup completion
velero backup get --schedule=<schedule-name>

# Monitor for any pod restarts
kubectl --context fzymgc-house get pods -n velero -w
```

Expected: Scheduled backups complete successfully, no unexpected pod restarts

**Step 2: Verify at least 2 scheduled backups completed**

Run:
```bash
velero backup get --schedule=<primary-schedule-name>
```

Expected: At least 2 new backups since upgrade with Phase: Completed

**Step 3: Check Grafana for any alerts**

Open: https://grafana.fzymgc.house
Search for: Velero alerts/metrics

Expected: No Velero-related alerts firing

**Step 4: Confirm readiness for Phase 2**

Checklist:
- [ ] 24-48 hours passed since Phase 1
- [ ] At least 2 scheduled backups completed
- [ ] No pod restarts or errors
- [ ] No alerts firing
- [ ] Backup metrics healthy in Grafana

If all checked: Proceed to Task 6

---

## Task 6: Phase 2 - Update Kubectl Image

**Prerequisites:** Phase 1 stable for 24-48 hours

**Files:**
- Modify: `argocd/cluster-app/templates/velero.yaml:80-83`

**Step 1: Update kubectl image repository**

File: `argocd/cluster-app/templates/velero.yaml`

Change lines 80-83:
```yaml
# Before:
                  kubectl:
                      image:
                          repository: bitnamilegacy/kubectl
                          tag: "1.33.4"

# After:
                  kubectl:
                      image:
                          repository: cgr.dev/chainguard/kubectl
                          tag: "latest-dev"
```

**Step 2: Validate YAML syntax**

Run:
```bash
yamllint argocd/cluster-app/templates/velero.yaml
```

Expected: No errors

**Step 3: Commit Phase 2 changes**

Run:
```bash
git add argocd/cluster-app/templates/velero.yaml
git commit -m "feat(velero): Phase 2 - Migrate kubectl to Chainguard

Phase 2 of 2-phase upgrade:
- Kubectl image: bitnamilegacy/kubectl:1.33.4 → cgr.dev/chainguard/kubectl:latest-dev
- Eliminates last Bitnami dependency
- Chainguard is actively maintained and security-focused

See docs/plans/2025-12-09-velero-chart-upgrade.md for full plan.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Expected: Commit created with changes

---

## Task 7: Phase 2 - Create Pull Request

**Files:**
- None (GitHub operations)

**Step 1: Push Phase 2 changes**

Run:
```bash
git push origin feat/velero-chart-upgrade
```

Expected: Changes pushed to existing branch

**Step 2: Create Phase 2 pull request**

Run:
```bash
gh pr create --title "feat(velero): Phase 2 - Migrate kubectl to Chainguard" --body "$(cat <<'EOF'
## Phase 2: Kubectl Image Migration

Migrates kubectl image from Bitnami to Chainguard, eliminating last Bitnami dependency.

### Changes
- Kubectl image: bitnamilegacy/kubectl:1.33.4 → cgr.dev/chainguard/kubectl:latest-dev

### Why Chainguard
- **Security-focused**: Minimal attack surface, regularly patched
- **Actively maintained**: Not deprecated like Bitnami
- **Community validated**: Confirmed working in vmware-tanzu/helm-charts#698
- **Has required tools**: `:latest-dev` includes shell and kubectl for upgrade-crds hook
- **Free**: No subscription for `:latest-dev` tag

### Prerequisites
- [x] Phase 1 stable for 24-48 hours
- [x] At least 2 scheduled backups completed successfully
- [x] No errors or alerts

### Impact
- Only affects upgrade-crds pre-upgrade hook job
- Main Velero pods unaffected
- Low risk change

### Validation Plan
After merge:
- [ ] ArgoCD syncs successfully
- [ ] upgrade-crds job completes with Chainguard image
- [ ] Test backup succeeds
- [ ] All pods remain healthy

### Rollback Plan
If issues occur:
\`\`\`bash
# Revert commit and ArgoCD auto-syncs back
git revert HEAD
git push origin main
\`\`\`

### References
- Design doc: docs/plans/2025-12-09-velero-chart-upgrade.md
- Chainguard kubectl: https://edu.chainguard.dev/chainguard/chainguard-images/reference/kubectl/

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR created with URL returned

**Step 3: Note PR number**

Copy PR URL for Phase 2 validation.

---

## Task 8: Phase 2 - Post-Merge Validation

**Prerequisites:** Phase 2 PR merged to main

**Files:**
- None (read-only validation)

**Step 1: Monitor ArgoCD sync**

Run:
```bash
kubectl --context fzymgc-house get application velero -n argocd -w
```

Expected: STATUS: Synced, HEALTH: Healthy
Press Ctrl+C when Healthy.

**Step 2: Verify no new pods created**

Run:
```bash
kubectl --context fzymgc-house get pods -n velero
```

Expected: Same 5 pods as Phase 1 (kubectl image only affects hook jobs)

**Step 3: Check if upgrade-crds job ran**

Run:
```bash
kubectl --context fzymgc-house get jobs -n velero -l helm.sh/hook=pre-upgrade
```

Expected: May see velero-upgrade-crds job (completed or not present if cleaned up)

**Step 4: If upgrade-crds job exists, check its image**

Run:
```bash
kubectl --context fzymgc-house get job velero-upgrade-crds -n velero -o jsonpath='{.spec.template.spec.initContainers[0].image}'
```

Expected: `docker.io/bitnamilegacy/kubectl:1.34` or similar
Note: This shows previous run. Next upgrade will use Chainguard.

**Step 5: Create test backup with new config**

Run:
```bash
velero backup create test-phase2-chainguard --include-namespaces=<test-namespace> --wait
```

Expected: Backup completed successfully

**Step 6: Verify test backup**

Run:
```bash
velero backup describe test-phase2-chainguard
```

Expected: Phase: Completed, Status: []

**Step 7: Verify no kubectl image in running pods**

Run:
```bash
# Kubectl image only used in upgrade-crds hook job, not main pods
kubectl --context fzymgc-house get pods -n velero -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u
```

Expected: Only velero/velero:v1.17.1 and velero/velero-plugin-for-aws images

**Step 8: Confirm Chainguard config in git**

Run:
```bash
grep -A 3 "kubectl:" argocd/cluster-app/templates/velero.yaml
```

Expected:
```yaml
kubectl:
    image:
        repository: cgr.dev/chainguard/kubectl
        tag: "latest-dev"
```

**Step 9: Document Phase 2 completion**

Create file: `docs/plans/2025-12-09-phase2-validation-results.md`

Content:
```markdown
# Phase 2 Validation Results

**Date:** $(date +%Y-%m-%d)
**Kubectl Image:** cgr.dev/chainguard/kubectl:latest-dev

## Health Checks ✓
- ArgoCD sync: Successful
- Pods running: 5/5 (unchanged from Phase 1)
- Test backup: Successful

## Configuration ✓
- Kubectl image updated in git config
- No Bitnami dependencies remaining
- Next upgrade-crds job will use Chainguard image

## Completion
Both phases complete:
- Phase 1: Chart 10.1.2 → 11.2.0 ✓
- Phase 2: Kubectl bitnami → chainguard ✓

All Bitnami dependencies eliminated.
```

Run:
```bash
git add docs/plans/2025-12-09-phase2-validation-results.md
git commit -m "docs: Phase 2 validation results

All validation checks passed:
- ArgoCD sync successful
- Test backup with Chainguard config successful
- All Bitnami dependencies eliminated

Upgrade complete.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
git push origin feat/velero-chart-upgrade
```

Expected: Phase 2 validation documented

---

## Task 9: Final Verification and Cleanup

**Prerequisites:** Both phases validated successfully

**Files:**
- None (verification only)

**Step 1: Verify no Bitnami references in config**

Run:
```bash
grep -i "bitnami" argocd/cluster-app/templates/velero.yaml
```

Expected: No matches (exit code 1)

**Step 2: Verify chart version**

Run:
```bash
grep "targetRevision:" argocd/cluster-app/templates/velero.yaml | grep velero
```

Expected: `targetRevision: 11.2.0`

**Step 3: Verify Velero app version**

Run:
```bash
kubectl --context fzymgc-house get deployment velero -n velero -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Expected: `velero/velero:v1.17.1`

**Step 4: Create final completion tag**

Run:
```bash
git tag velero-11.2.0-complete
git push origin velero-11.2.0-complete
```

Expected: Tag created marking successful upgrade completion

**Step 5: Update success metrics in design doc**

File: `docs/plans/2025-12-09-velero-chart-upgrade.md`

Mark all success metrics as complete in the "Success Metrics" section.

**Step 6: Commit final updates**

Run:
```bash
git add docs/plans/2025-12-09-velero-chart-upgrade.md
git commit -m "docs: Mark upgrade complete with all success metrics

Both phases completed successfully:
- Chart upgraded: 10.1.2 → 11.2.0
- Velero upgraded: 1.16.2 → 1.17.1
- Kubectl migrated: bitnami → chainguard
- All validation passed
- No Bitnami dependencies remaining

Tagged as: velero-11.2.0-complete

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
git push origin feat/velero-chart-upgrade
```

Expected: Final documentation committed

**Step 7: Clean up test backups**

Run:
```bash
velero backup delete test-phase1-upgrade --confirm
velero backup delete test-phase2-chainguard --confirm
velero restore delete test-phase1-restore --confirm
```

Expected: Test artifacts cleaned up

**Step 8: Verify final state**

Run:
```bash
echo "=== Velero Upgrade Complete ==="
echo "Chart version: 11.2.0"
echo "Velero version: 1.17.1"
echo "Kubectl image: cgr.dev/chainguard/kubectl:latest-dev"
echo "Bitnami dependencies: ELIMINATED"
echo ""
echo "ArgoCD status:"
kubectl --context fzymgc-house get application velero -n argocd
echo ""
echo "Pod health:"
kubectl --context fzymgc-house get pods -n velero
echo ""
echo "Recent backups:"
velero backup get | head -n 10
```

Expected: Summary showing successful upgrade state

---

## Rollback Procedures

### If Phase 1 Needs Rollback

**Step 1: Identify issue and decide to rollback**

Document what went wrong before rolling back.

**Step 2: Revert Phase 1 commit**

Run:
```bash
# Find the Phase 1 commit hash
git log --oneline -10

# Revert it
git revert <phase1-commit-hash>
git push origin main
```

Expected: ArgoCD auto-syncs back to 10.1.2 within 3 minutes

**Step 3: Monitor rollback**

Run:
```bash
kubectl --context fzymgc-house get application velero -n argocd -w
```

Expected: Syncs back to old version, pods restart with old image

**Step 4: Verify rollback complete**

Run:
```bash
kubectl --context fzymgc-house get deployment velero -n velero -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Expected: `velero/velero:v1.16.2`

**Step 5: Verify backups still accessible**

Run:
```bash
velero backup get
velero backup describe <latest-backup>
```

Expected: All backups accessible

**Step 6: Document rollback**

Create: `docs/plans/2025-12-09-phase1-rollback.md`

Document:
- What went wrong
- When rollback occurred
- Current state after rollback
- Next steps

### If Phase 2 Needs Rollback

**Step 1: Revert Phase 2 commit**

Run:
```bash
git revert <phase2-commit-hash>
git push origin main
```

Expected: ArgoCD syncs kubectl image back to bitnamilegacy

**Step 2: Verify rollback**

Run:
```bash
grep -A 3 "kubectl:" argocd/cluster-app/templates/velero.yaml
```

Expected: Shows bitnamilegacy/kubectl:1.33.4

---

## Notes for Engineer

### Testing Philosophy
- TDD not strictly applicable here (infrastructure changes)
- Validation steps serve as "tests"
- Each phase is validated before proceeding

### Commit Frequency
- Commit after each major step
- Commits should be atomic and revertible
- Use conventional commits format

### ArgoCD Auto-Sync
- Auto-sync enabled, changes apply within 3 minutes of merge
- Can force sync with kubectl patch if needed
- Monitor sync status with `-w` (watch) flag

### Velero CLI
- Requires velero CLI installed: `brew install velero`
- Must be authenticated to cluster
- Uses kubeconfig context: fzymgc-house

### Git Tags
- velero-10.1.2-working: Pre-upgrade state
- velero-11.2.0-complete: Post-upgrade state
- Use for easy rollback: `git reset --hard <tag>`

### Waiting Periods
- Phase 1 → Phase 2: 24-48 hours minimum
- Allows scheduled backups to prove stability
- Do not rush - backup system is critical

### If Stuck
- Check ArgoCD UI: https://argocd.fzymgc.house
- Check Velero logs: `kubectl logs -n velero deployment/velero`
- Consult design doc: docs/plans/2025-12-09-velero-chart-upgrade.md
- Rollback is always safe option
