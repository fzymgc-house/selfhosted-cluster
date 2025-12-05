# K3s System Upgrade Controller Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy the System Upgrade Controller via ArgoCD to enable declarative k3s upgrades, then upgrade the cluster from v1.32.5+k3s1 to v1.34.2+k3s1.

**Architecture:** ArgoCD Application deploys the SUC controller and upgrade Plans to the `system-upgrade` namespace. Plans target control-plane nodes first, then workers. Version changes in git trigger upgrades automatically.

**Tech Stack:** Kubernetes, ArgoCD, Rancher System Upgrade Controller, Kustomize

---

### Task 1: Create system-upgrade namespace manifest

**Files:**
- Create: `argocd/app-configs/system-upgrade/namespace.yaml`

**Step 1: Create the namespace manifest**

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: system-upgrade
  labels:
    app.kubernetes.io/name: system-upgrade
  annotations:
    argocd.argoproj.io/sync-wave: "-100"
```

**Step 2: Verify YAML syntax**

Run: `kubectl apply --dry-run=client -f argocd/app-configs/system-upgrade/namespace.yaml`
Expected: `namespace/system-upgrade created (dry run)`

**Step 3: Commit**

```bash
git add argocd/app-configs/system-upgrade/namespace.yaml
git commit -m "feat(system-upgrade): Add namespace manifest"
```

---

### Task 2: Create controller deployment manifest

**Files:**
- Create: `argocd/app-configs/system-upgrade/controller.yaml`

**Step 1: Create the controller manifest**

This includes the CRD, ServiceAccount, ClusterRoleBinding, ConfigMap, and Deployment.

```yaml
---
# ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: system-upgrade
  namespace: system-upgrade
  annotations:
    argocd.argoproj.io/sync-wave: "-100"
---
# ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system-upgrade
  annotations:
    argocd.argoproj.io/sync-wave: "-100"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: system-upgrade
    namespace: system-upgrade
---
# ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: default-controller-env
  namespace: system-upgrade
  annotations:
    argocd.argoproj.io/sync-wave: "-100"
data:
  SYSTEM_UPGRADE_CONTROLLER_DEBUG: "false"
  SYSTEM_UPGRADE_CONTROLLER_THREADS: "2"
  SYSTEM_UPGRADE_JOB_ACTIVE_DEADLINE_SECONDS: "900"
  SYSTEM_UPGRADE_JOB_BACKOFF_LIMIT: "99"
  SYSTEM_UPGRADE_JOB_IMAGE_PULL_POLICY: "Always"
  SYSTEM_UPGRADE_JOB_KUBECTL_IMAGE: "rancher/kubectl:v1.29.2"
  SYSTEM_UPGRADE_JOB_PRIVILEGED: "true"
  SYSTEM_UPGRADE_JOB_TTL_SECONDS_AFTER_FINISH: "900"
  SYSTEM_UPGRADE_PLAN_POLLING_INTERVAL: "15m"
---
# Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: system-upgrade-controller
  namespace: system-upgrade
  annotations:
    argocd.argoproj.io/sync-wave: "-100"
spec:
  selector:
    matchLabels:
      app: system-upgrade-controller
  template:
    metadata:
      labels:
        app: system-upgrade-controller
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: node-role.kubernetes.io/control-plane
                    operator: In
                    values:
                      - "true"
      serviceAccountName: system-upgrade
      tolerations:
        - key: CriticalAddonsOnly
          operator: Exists
        - key: node-role.kubernetes.io/master
          operator: Exists
          effect: NoSchedule
        - key: node-role.kubernetes.io/controlplane
          operator: Exists
          effect: NoSchedule
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
        - key: node-role.kubernetes.io/etcd
          operator: Exists
          effect: NoExecute
      containers:
        - name: system-upgrade-controller
          image: rancher/system-upgrade-controller:v0.14.2
          imagePullPolicy: IfNotPresent
          securityContext:
            runAsNonRoot: true
            runAsUser: 65534
            runAsGroup: 65534
            allowPrivilegeEscalation: false
            seccompProfile:
              type: RuntimeDefault
            capabilities:
              drop:
                - ALL
          envFrom:
            - configMapRef:
                name: default-controller-env
          env:
            - name: SYSTEM_UPGRADE_CONTROLLER_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.labels['app']
            - name: SYSTEM_UPGRADE_CONTROLLER_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
          volumeMounts:
            - name: etc-ssl
              mountPath: /etc/ssl
              readOnly: true
            - name: etc-pki
              mountPath: /etc/pki
              readOnly: true
            - name: etc-ca-certificates
              mountPath: /etc/ca-certificates
              readOnly: true
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: etc-ssl
          hostPath:
            path: /etc/ssl
            type: DirectoryOrCreate
        - name: etc-pki
          hostPath:
            path: /etc/pki
            type: DirectoryOrCreate
        - name: etc-ca-certificates
          hostPath:
            path: /etc/ca-certificates
            type: DirectoryOrCreate
        - name: tmp
          emptyDir: {}
```

**Step 2: Verify YAML syntax**

Run: `kubectl apply --dry-run=client -f argocd/app-configs/system-upgrade/controller.yaml`
Expected: Multiple resources created (dry run)

**Step 3: Commit**

```bash
git add argocd/app-configs/system-upgrade/controller.yaml
git commit -m "feat(system-upgrade): Add controller deployment manifest"
```

---

### Task 3: Create server upgrade plan

**Files:**
- Create: `argocd/app-configs/system-upgrade/plan-server.yaml`

**Step 1: Create the server plan manifest**

```yaml
---
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: k3s-server
  namespace: system-upgrade
  annotations:
    argocd.argoproj.io/sync-wave: "-99"
spec:
  concurrency: 1
  cordon: true
  nodeSelector:
    matchExpressions:
      - key: node-role.kubernetes.io/control-plane
        operator: In
        values:
          - "true"
  serviceAccountName: system-upgrade
  upgrade:
    image: rancher/k3s-upgrade
  version: v1.34.2+k3s1
```

**Step 2: Verify YAML syntax**

Run: `kubectl apply --dry-run=client -f argocd/app-configs/system-upgrade/plan-server.yaml`
Expected: `plan.upgrade.cattle.io/k3s-server created (dry run)`

**Step 3: Commit**

```bash
git add argocd/app-configs/system-upgrade/plan-server.yaml
git commit -m "feat(system-upgrade): Add server upgrade plan for v1.34.2"
```

---

### Task 4: Create agent upgrade plan

**Files:**
- Create: `argocd/app-configs/system-upgrade/plan-agent.yaml`

**Step 1: Create the agent plan manifest**

```yaml
---
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: k3s-agent
  namespace: system-upgrade
  annotations:
    argocd.argoproj.io/sync-wave: "-99"
spec:
  concurrency: 1
  cordon: true
  nodeSelector:
    matchExpressions:
      - key: node-role.kubernetes.io/control-plane
        operator: DoesNotExist
  prepare:
    args:
      - prepare
      - k3s-server
    image: rancher/k3s-upgrade
  serviceAccountName: system-upgrade
  upgrade:
    image: rancher/k3s-upgrade
  version: v1.34.2+k3s1
```

**Step 2: Verify YAML syntax**

Run: `kubectl apply --dry-run=client -f argocd/app-configs/system-upgrade/plan-agent.yaml`
Expected: `plan.upgrade.cattle.io/k3s-agent created (dry run)`

**Step 3: Commit**

```bash
git add argocd/app-configs/system-upgrade/plan-agent.yaml
git commit -m "feat(system-upgrade): Add agent upgrade plan for v1.34.2"
```

---

### Task 5: Create kustomization

**Files:**
- Create: `argocd/app-configs/system-upgrade/kustomization.yaml`

**Step 1: Create the kustomization manifest**

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: system-upgrade
resources:
  - namespace.yaml
  - controller.yaml
  - plan-server.yaml
  - plan-agent.yaml
```

**Step 2: Verify kustomize build**

Run: `kubectl kustomize argocd/app-configs/system-upgrade/`
Expected: Combined YAML output with all resources

**Step 3: Commit**

```bash
git add argocd/app-configs/system-upgrade/kustomization.yaml
git commit -m "feat(system-upgrade): Add kustomization"
```

---

### Task 6: Create ArgoCD Application

**Files:**
- Create: `argocd/cluster-app/templates/system-upgrade.yaml`

**Step 1: Create the ArgoCD Application manifest**

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: system-upgrade
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-100"
spec:
  project: core-services
  sources:
    - repoURL: https://github.com/fzymgc-house/selfhosted-cluster
      targetRevision: HEAD
      path: argocd/app-configs/system-upgrade
  destination:
    server: https://kubernetes.default.svc
    namespace: system-upgrade
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=true
```

**Step 2: Verify YAML syntax**

Run: `kubectl apply --dry-run=client -f argocd/cluster-app/templates/system-upgrade.yaml`
Expected: `application.argoproj.io/system-upgrade created (dry run)`

**Step 3: Commit**

```bash
git add argocd/cluster-app/templates/system-upgrade.yaml
git commit -m "feat(system-upgrade): Add ArgoCD Application"
```

---

### Task 7: Add Plan CRD

**Files:**
- Create: `argocd/app-configs/system-upgrade/crd.yaml`
- Modify: `argocd/app-configs/system-upgrade/kustomization.yaml`

**Step 1: Create the CRD manifest**

Run: `curl -sL https://github.com/rancher/system-upgrade-controller/releases/latest/download/crd.yaml > argocd/app-configs/system-upgrade/crd.yaml`

**Step 2: Add sync-wave annotation to CRD**

Edit `argocd/app-configs/system-upgrade/crd.yaml` to add annotation:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-100"
  name: plans.upgrade.cattle.io
```

**Step 3: Update kustomization to include CRD first**

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: system-upgrade
resources:
  - crd.yaml
  - namespace.yaml
  - controller.yaml
  - plan-server.yaml
  - plan-agent.yaml
```

**Step 4: Verify kustomize build**

Run: `kubectl kustomize argocd/app-configs/system-upgrade/`
Expected: Combined YAML with CRD first

**Step 5: Commit**

```bash
git add argocd/app-configs/system-upgrade/crd.yaml argocd/app-configs/system-upgrade/kustomization.yaml
git commit -m "feat(system-upgrade): Add Plan CRD"
```

---

### Task 8: Push and create PR

**Files:**
- None (git operations only)

**Step 1: Push branch**

```bash
git push -u origin feat/k3s-system-upgrade-controller
```

**Step 2: Create PR**

```bash
gh pr create --title "feat: Add System Upgrade Controller for k3s upgrades" --body "## Summary

Deploys the Rancher System Upgrade Controller via ArgoCD to enable declarative k3s upgrades.

## Changes

- New ArgoCD application: system-upgrade
- Deploys SUC controller to system-upgrade namespace
- Server plan upgrades control-plane nodes to v1.34.2+k3s1
- Agent plan upgrades worker nodes after control-plane complete

## Upgrade Process

After merge:
1. ArgoCD syncs the system-upgrade application
2. SUC controller deploys
3. Plans trigger upgrade from v1.32.5 to v1.34.2
4. Control-plane nodes upgrade first (one at a time)
5. Worker nodes upgrade after control-plane complete

## Monitoring

\`\`\`bash
kubectl get plans -n system-upgrade -w
kubectl get nodes -w
kubectl logs -n system-upgrade -l app=system-upgrade-controller -f
\`\`\`

## Related

- Design: docs/plans/2025-12-05-k3s-upgrade-system-design.md
- Issue #97: Requires k8s 1.33+ for ImageVolume extensions

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

---

### Task 9: Monitor upgrade after merge

**Files:**
- None (monitoring only)

**Step 1: Watch ArgoCD sync**

Run: `kubectl --context fzymgc-house get application system-upgrade -n argocd -w`
Expected: Application syncs and becomes Healthy

**Step 2: Watch plans**

Run: `kubectl --context fzymgc-house get plans -n system-upgrade -w`
Expected: Plans show progress as nodes upgrade

**Step 3: Watch nodes**

Run: `kubectl --context fzymgc-house get nodes -w`
Expected: Nodes cycle through SchedulingDisabled → Ready with new version

**Step 4: Verify final state**

Run: `kubectl --context fzymgc-house get nodes -o wide`
Expected: All nodes show `v1.34.2+k3s1`
