# GitHub Actions Runner Controller Migration Plan

**Last Updated**: 2025-12-07
**Status**: Planning Complete - Ready for Implementation
**Related Issue**: #129

## Executive Summary

Migrate from deprecated `actions-runner-controller` (summerwind.dev) to the official GitHub ARC (Actions Runner Controller) using the new `gha-runner-scale-set` architecture.

**Why Migration is Needed**:
- Current controller is deprecated and failing to sync
- Using outdated API (`actions.summerwind.dev/v1alpha1`)
- Blocking Windmill production deployment automation (#137)
- GitHub's official ARC provides better scaling and security

## Current State

### What's Broken ❌

**Existing Configuration**:
- Chart: `actions-runner-controller` v0.23.7 (DEPRECATED)
- API: `actions.summerwind.dev/v1alpha1` (OLD)
- Status: ArgoCD sync failing, runners not deploying
- Location: `argocd/app-configs/actions-runner-controller/`

**ArgoCD Application Status**:
```
Health Status: Degraded
Sync Status: OutOfSync
Error: Failed sync attempt (retried 5 times)
```

### What Works ✅

- GitHub token exists in Vault: `secret/fzymgc-house/cluster/github`
- ExternalSecret configuration is correct
- Token has proper permissions for runner registration

## Target Architecture

### Two-Component Design

**Component 1: Controller Operator**
- **Purpose**: Cluster-wide operator managing all runner scale sets
- **Chart**: `ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller`
- **Version**: 0.9.3 (latest stable)
- **Namespace**: `arc-systems`
- **Replicas**: 1 (single controller for entire cluster)

**Component 2: Runner Scale Set**
- **Purpose**: Organization-scoped autoscaling runners
- **Chart**: `ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set`
- **Version**: 0.9.3 (latest stable)
- **Namespace**: `arc-runners`
- **Scope**: Organization-wide (`fzymgc-house` org)

### Key Design Decisions

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| **Namespace Organization** | Follow GitHub convention (arc-systems + arc-runners) | Clean separation, matches official docs |
| **Runner Scope** | Organization-scoped (fzymgc-house org) | Allows reuse across all repos, better resource utilization |
| **Scaling Strategy** | Autoscaling (queue-based) | Efficient resource usage, handles workflow bursts |
| **Scale Limits** | 0-3 runners | Scale to zero when idle, conservative for homelab |
| **Runner Labels** | `fzymgc-house`, `self-hosted-cluster`, `windmill-sync` | Maximum targeting flexibility, maintains compatibility |
| **Runner Lifecycle** | Ephemeral (destroyed after each job) | Enhanced security, clean state per job |

## Implementation Plan

### Phase 1: Prepare Configuration

**Create Directory Structure**:
```
argocd/app-configs/
├── arc-controller/
│   ├── namespace.yaml
│   ├── kustomization.yaml
│   └── values.yaml
└── arc-runners/
    ├── namespace.yaml
    ├── kustomization.yaml
    ├── values.yaml
    └── github-token-secret.yaml
```

**Create ArgoCD Applications**:
```
argocd/cluster-app/templates/
├── arc-controller.yaml
└── arc-runners.yaml
```

**Git Workflow**:
1. Create feature branch: `feat/migrate-arc-runner`
2. Commit all configuration files
3. Push and create PR

**Estimated Time**: 1 hour

### Phase 2: Deploy Controller

**Steps**:
1. ArgoCD detects new application and syncs
2. Creates `arc-systems` namespace
3. Deploys controller pod

**Verification Commands**:
```bash
# Check controller pod status
kubectl --context fzymgc-house get pods -n arc-systems

# View controller logs
kubectl --context fzymgc-house logs -n arc-systems -l app.kubernetes.io/name=gha-runner-scale-set-controller

# Verify CRDs installed
kubectl --context fzymgc-house get crd | grep actions.github.com
```

**Expected Output**:
- Controller pod in Running state
- No errors in logs
- AutoscalingRunnerSet CRD present

**Estimated Time**: 15 minutes

### Phase 3: Deploy Runners

**Steps**:
1. ArgoCD syncs arc-runners application
2. ExternalSecret creates github-token from Vault
3. Runner scale set registers with GitHub
4. Initial runner pod may start (or wait for first workflow)

**Verification Commands**:
```bash
# Check ExternalSecret sync
kubectl --context fzymgc-house get externalsecret -n arc-runners
kubectl --context fzymgc-house describe externalsecret github-token -n arc-runners

# Check runner scale set registration
kubectl --context fzymgc-house get pods -n arc-runners

# View runner logs
kubectl --context fzymgc-house logs -n arc-runners -l app.kubernetes.io/name=gha-runner-scale-set
```

**GitHub UI Verification**:
1. Go to https://github.com/organizations/fzymgc-house/settings/actions/runners
2. Look for "fzymgc-house-cluster-runners" in runner list
3. Status should show "Idle" (ready for jobs)

**Expected Output**:
- ExternalSecret synced successfully
- Runner scale set registered in GitHub UI
- No error logs

**Estimated Time**: 15 minutes

### Phase 4: Test & Validate

**Create Test Workflow** (`.github/workflows/test-arc-runner.yaml`):
```yaml
name: Test ARC Runner

on:
  workflow_dispatch:

jobs:
  test:
    runs-on: [self-hosted, windmill-sync]
    steps:
      - name: Test runner
        run: |
          echo "Runner hostname: $(hostname)"
          echo "Runner OS: $(uname -a)"
          echo "Runner working directory: $(pwd)"
          echo "Test successful!"
```

**Verification Steps**:
1. Trigger workflow manually from GitHub UI
2. Watch runner pod creation: `kubectl --context fzymgc-house get pods -n arc-runners -w`
3. Verify workflow completes successfully
4. Verify runner pod is deleted after job completion

**Success Criteria**:
- ✅ Runner pod appears in arc-runners namespace
- ✅ Workflow completes successfully
- ✅ Runner pod is automatically deleted
- ✅ GitHub shows job ran on self-hosted runner

**Estimated Time**: 15 minutes

### Phase 5: Update Windmill Workflows

**Update Existing Workflows**:
- `.github/workflows/windmill-open-pr.yaml` - Already uses correct labels
- `.github/workflows/windmill-deploy-prod.yaml` - Already uses correct labels

**Verification**:
1. Trigger Windmill staging deployment
2. Verify workflow uses new ARC runner
3. Verify successful deployment to production workspace

**Success Criteria**:
- ✅ Windmill workflows run on new runners
- ✅ Production deployment automation works end-to-end

**Estimated Time**: 10 minutes

### Phase 6: Cleanup Old Controller

**Steps**:
1. Delete old ArgoCD application:
   ```bash
   kubectl --context fzymgc-house delete application actions-runner-controller -n argocd
   ```

2. Verify namespace cleanup (ArgoCD should auto-prune):
   ```bash
   kubectl --context fzymgc-house get namespace actions-runner-system
   ```

3. If namespace doesn't auto-delete, manually remove:
   ```bash
   kubectl --context fzymgc-house delete namespace actions-runner-system
   ```

4. Archive old configuration:
   ```bash
   mkdir argocd/app-configs/actions-runner-controller/deprecated
   mv argocd/app-configs/actions-runner-controller/*.yaml argocd/app-configs/actions-runner-controller/deprecated/
   ```

5. Merge PR to main branch

**Estimated Time**: 10 minutes

## Configuration Details

### Controller Helm Values

**File**: `argocd/app-configs/arc-controller/values.yaml`

```yaml
# Minimal configuration - controller runs cluster-wide
replicaCount: 1

resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi

# Pod security for homelab cluster
securityContext:
  runAsNonRoot: true
  runAsUser: 1000

# Metrics for Prometheus scraping
metrics:
  controllerManagerAddr: ":8080"
  listenerAddr: ":8080"
  listenerEndpoint: "/metrics"
```

### Runner Scale Set Helm Values

**File**: `argocd/app-configs/arc-runners/values.yaml`

```yaml
# GitHub configuration
githubConfigUrl: "https://github.com/fzymgc-house"
githubConfigSecret: github-token

# Runner scale set name (visible in GitHub UI)
runnerScaleSetName: "fzymgc-house-cluster-runners"

# Autoscaling configuration
minRunners: 0
maxRunners: 3

# Runner labels for workflow targeting
runnerGroup: "default"
labels:
  - fzymgc-house
  - self-hosted-cluster
  - windmill-sync

# Ephemeral runners (destroyed after each job)
template:
  spec:
    ephemeral: true
    containers:
      - name: runner
        image: ghcr.io/actions/actions-runner:latest
        imagePullPolicy: IfNotPresent
        resources:
          limits:
            cpu: "2"
            memory: 4Gi
          requests:
            cpu: "1"
            memory: 2Gi
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000

# Pod security
containerMode:
  type: "kubernetes"
  kubernetesModeWorkVolumeClaim:
    accessModes: ["ReadWriteOnce"]
    storageClassName: "longhorn"
    resources:
      requests:
        storage: 10Gi
```

### ExternalSecret Configuration

**File**: `argocd/app-configs/arc-runners/github-token-secret.yaml`

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: github-token
  namespace: arc-runners
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: github-token
    creationPolicy: Owner
    template:
      type: Opaque
      data:
        github_token: "{{ .github_token }}"
  data:
    - secretKey: github_token
      remoteRef:
        key: secret/fzymgc-house/cluster/github
        property: windmill_actions_runner_token
```

## ArgoCD Application Definitions

### Controller Application

**File**: `argocd/cluster-app/templates/arc-controller.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: arc-controller
  namespace: argocd
spec:
  project: default
  sources:
    - repoURL: ghcr.io/actions/actions-runner-controller-charts
      chart: gha-runner-scale-set-controller
      targetRevision: 0.9.3
      helm:
        valueFiles:
          - $values/argocd/app-configs/arc-controller/values.yaml
    - repoURL: https://github.com/fzymgc-house/selfhosted-cluster
      targetRevision: HEAD
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: arc-systems
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Runners Application

**File**: `argocd/cluster-app/templates/arc-runners.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: arc-runners
  namespace: argocd
spec:
  project: default
  sources:
    - repoURL: ghcr.io/actions/actions-runner-controller-charts
      chart: gha-runner-scale-set
      targetRevision: 0.9.3
      helm:
        valueFiles:
          - $values/argocd/app-configs/arc-runners/values.yaml
    - repoURL: https://github.com/fzymgc-house/selfhosted-cluster
      targetRevision: HEAD
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: arc-runners
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## Risk Assessment

### Low Risk ✅

- **New namespaces**: Controller and runners deploy in new namespaces, no conflict with existing resources
- **GitOps workflow**: All changes committed to Git, reviewable in PR before deployment
- **Incremental deployment**: Can test without affecting existing (broken) controller
- **Rollback capability**: Can delete new applications and investigate issues without losing old config

### Medium Risk ⚠️

- **Token permissions**: GitHub token must have correct permissions for organization-wide runners
  - **Mitigation**: Token already exists and worked for repo-scoped runners, should work for org-scoped
- **Resource limits**: Runners configured with 2 CPU / 4Gi memory limits
  - **Mitigation**: Conservative limits appropriate for homelab, can adjust if needed
- **Storage requirements**: Each runner gets 10Gi Longhorn volume
  - **Mitigation**: Ephemeral runners clean up after jobs, volume reclaimed

### Mitigations

1. **Test workflow first**: Run simple test workflow before enabling production Windmill automation
2. **Monitor resource usage**: Watch CPU/memory/storage during first few workflow runs
3. **Keep old config**: Archive old configuration in `deprecated/` folder for reference
4. **Document changes**: This migration plan provides complete rollback instructions

## Success Metrics

### Immediate Success (Phase 4)
- ✅ Controller pod running in arc-systems
- ✅ Runner scale set registered in GitHub UI
- ✅ Test workflow completes successfully
- ✅ Runner pod auto-deleted after job

### Long-term Success (Post-Migration)
- ✅ Windmill production deployment automation working
- ✅ Runners scaling 0-3 based on workflow demand
- ✅ No manual intervention required for deployments
- ✅ All workflows using self-hosted runners complete successfully

## Timeline

**Total Estimated Time**: ~1.5 hours

| Phase | Task | Time |
|-------|------|------|
| 1 | Create configuration files and PR | 1 hour |
| 2 | Deploy controller | 15 min |
| 3 | Deploy runners | 15 min |
| 4 | Test and validate | 15 min |
| 5 | Update Windmill workflows | 10 min |
| 6 | Cleanup old controller | 10 min |

## Related Issues

- **#129**: Deploy GitHub Actions Runner Controller (THIS ISSUE - will be updated)
- **#137**: Create GitHub Actions workflow for wmill sync (COMPLETED - needs working runner)
- **Windmill Migration**: See `windmill/DEPLOYMENT_STATUS.md`

## Rollback Plan

If migration fails:

1. **Keep old ArgoCD application**: Don't delete until new system proven
2. **Delete new applications**:
   ```bash
   kubectl delete application arc-controller -n argocd
   kubectl delete application arc-runners -n argocd
   ```
3. **Clean up namespaces**:
   ```bash
   kubectl delete namespace arc-systems
   kubectl delete namespace arc-runners
   ```
4. **Investigate failures**: Check logs, GitHub runner registration, token permissions
5. **Retry or adjust configuration**: Fix issues and re-attempt deployment

## Post-Migration Tasks

1. **Update documentation**:
   - Update main README.md with new ARC architecture
   - Document runner labels and usage patterns
   - Update troubleshooting guide

2. **Monitor performance**:
   - Watch runner scaling behavior over first week
   - Adjust min/max runners if needed
   - Monitor resource usage and storage consumption

3. **Close related issues**:
   - Close #129 (ARC deployment)
   - Verify #137 workflows working with new runners

4. **Expand usage**:
   - Consider adding additional runner scale sets for different workload types
   - Explore using runners for other repos in fzymgc-house org
