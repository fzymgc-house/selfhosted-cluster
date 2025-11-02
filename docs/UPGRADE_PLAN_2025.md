# Infrastructure Upgrade Plan - November 2025

**Created:** 2025-11-01
**Status:** In Progress
**Estimated Completion:** 7 weeks from start

## Overview

This document tracks the systematic upgrade of all infrastructure components across Ansible, ArgoCD, and Terraform managed resources.

## Upgrade Principles

1. One component at a time
2. Test after each change
3. Create separate branch for each component
4. Monitor for 24-48 hours before proceeding to next component
5. Full backup before each phase

---

## Phase 1: Foundation & Prerequisites ✅ COMPLETED

### Pre-Flight Checklist
- [ ] Full Velero backup created
- [ ] Current state documented
- [ ] Vault health verified
- [ ] Rollback procedures tested

### 1.1 Ansible Collections Update
**Status:** ⏳ Not Started
**Branch:** `upgrade/ansible-collections`
**Files:** `ansible/requirements-ansible.yml`
**Current:** kubernetes.core >=5.0.0
**Target:** kubernetes.core >=6.2.0

### 1.2 cert-manager Update
**Status:** ✅ Completed
**Branch:** `upgrade/cert-manager-v1.19.1`
**PR:** #34
**Files:** `ansible/roles/k3sup/tasks/cert-manager.yml`
**Current:** v1.18.2
**Target:** v1.19.1
**Notes:**
- Skip v1.19.0 due to certificate re-issue bug
- Go directly to v1.19.1
- Wait 10 minutes after upgrade
- Verify all certificates: `kubectl get certificates -A`
- Verify certificate requests: `kubectl get certificaterequests -A`

**Rollback:**
```bash
# Revert chart_version to v1.18.2 in ansible/roles/k3sup/tasks/cert-manager.yml
ansible-playbook -i inventory/hosts.yml k3s-playbook.yml --tags cert-manager
```

### 1.3 External Secrets Operator Update
**Status:** ✅ Completed
**Branch:** `upgrade/external-secrets-v0.20.4`
**PR:** #36
**Files:** `ansible/roles/k3sup/tasks/external-secrets-operator.yml`
**Current:** 0.19.2
**Target:** 0.20.4

### 1.4 MetalLB Update
**Status:** ✅ Completed
**Branch:** `upgrade/metallb-v0.15.2`
**PR:** #37
**Files:**
- `ansible/roles/k3sup/tasks/metallb.yml`
- `argocd/cluster-app/templates/metallb.yaml`
**Current:** v0.14.9
**Target:** v0.15.2

---

## Phase 2: Core Infrastructure (Week 2) ✅ CURRENT PHASE

### 2.1 ArgoCD Update
**Status:** 🔄 In Progress
**Branch:** `upgrade/argocd-v9.0.5`
**Files:** `ansible/roles/k3sup/tasks/argocd.yml`
**Current:** 8.3.0
**Target:** 9.0.5
**Priority:** 🟡 Medium
**Notes:** Review breaking changes in 9.x release notes

### 2.2 Prometheus CRDs Update
**Status:** ⏳ Not Started
**Branch:** `upgrade/prometheus-crds-v79.1.0`
**Current:** 23.0.0
**Target:** 79.1.0
**Priority:** 🟡 Medium
**Notes:** MUST update before kube-prometheus-stack

### 2.3 Longhorn Update
**Status:** ⏳ Not Started
**Branch:** `upgrade/longhorn-v1.10.1`
**Current:** 1.9.1
**Target:** 1.10.1
**Priority:** 🔴 High
**Notes:**
- Manual CR migration required
- Skip v1.10.0 (critical bug)
- Use hotfixed image if needed
- Allow 30-60 minutes for completion
**Warning:** ⚠️ Read upgrade guide: https://longhorn.io/docs/1.10.0/deploy/upgrade/

### 2.4 Core ArgoCD Apps
**Status:** ⏳ Not Started
**Branch:** `upgrade/argocd-core-apps`
**Components:** metallb, reloader

---

## Phase 3: Observability Stack (Week 3)

### 3.1 kube-prometheus-stack
**Status:** ⏳ Not Started
**Branch:** `upgrade/kube-prometheus-stack-v79.1.0`
**Current:** 77.6.1
**Target:** 79.1.0
**Priority:** 🟡 Medium

### 3.2 Loki
**Status:** ⏳ Not Started
**Branch:** `upgrade/loki-v6.45.2`
**Current:** 6.40.0
**Target:** 6.45.2
**Priority:** 🟡 Medium

### 3.3 Grafana Operator
**Status:** ⏳ Not Started
**Branch:** `upgrade/grafana-operator-v5.20.0`
**Current:** v5.19.4
**Target:** v5.20.0
**Priority:** 🟢 Low

### 3.4 Grafana Alloy
**Status:** ⏳ Not Started
**Branch:** `upgrade/grafana-alloy-v1.2.1`
**Current:** 1.2.1
**Target:** 1.2.1 (verify if newer)
**Priority:** 🟢 Low

---

## Phase 4: Core Services (Week 4)

### 4.1 Vault
**Status:** ⏳ Not Started
**Branch:** `upgrade/vault-v0.31.0`
**Current:** 0.30.0
**Target:** 0.31.0
**Priority:** 🟡 Medium
**Warning:** ⚠️ CRITICAL - Backup Vault data first

### 4.2 CNPG
**Status:** ⏳ Not Started
**Branch:** `upgrade/cnpg-v0.26.1`
**Current:** 0.26.0
**Target:** 0.26.1
**Priority:** 🟢 Low

### 4.3 Valkey
**Status:** ⏳ Blocked - Decision Needed
**Branch:** TBD
**Current:** 3.0.31
**Target:** 4.1.3 OR migrate to alternative
**Priority:** 🟡 Medium
**Decision Required:**
- ⚠️ Bitnami requires commercial subscription after Aug 28, 2025
- Option A: Accept subscription
- Option B: Migrate to official Valkey images or alternative

---

## Phase 5: Auth & Applications (Week 5)

### 5.1 Authentik
**Status:** ⏳ Not Started
**Branch:** `upgrade/authentik-v2025.10.0`
**Current:** 2025.6.1
**Target:** 2025.10.0
**Priority:** 🟡 Medium

### 5.2 Argo Workflows
**Status:** ⏳ Not Started
**Branch:** `upgrade/argo-workflows-v0.45.27`
**Current:** 0.45.24
**Target:** 0.45.27
**Priority:** 🟢 Low

### 5.3 Windmill
**Status:** ⏳ Not Started
**Branch:** `upgrade/windmill-v2.0.495`
**Current:** 2.0.488
**Target:** 2.0.495
**Priority:** 🟢 Low
**Warning:** Do NOT upgrade to 3.x without extensive testing

---

## Phase 6: Networking & Backup (Week 6)

### 6.1 Traefik
**Status:** ⏳ Not Started
**Branch:** `upgrade/traefik-v37.2.0`
**Current:** 35.4.0
**Target:** 37.2.0
**Priority:** 🟡 Medium
**Warning:** ⚠️ Major version jump - review 36.x and 37.x release notes

### 6.2 Velero
**Status:** ⏳ Not Started
**Branch:** `upgrade/velero-v11.1.1`
**Current:** 10.1.2
**Target:** 11.1.1
**Priority:** 🟡 Medium

---

## Component Status Legend

- ⏳ Not Started
- 🔄 In Progress
- ✅ Completed
- ⏸️ Paused
- ❌ Failed/Rolled Back
- 🚫 Blocked

## Priority Legend

- 🔴 High - Security/Stability critical
- 🟡 Medium - Feature updates, bug fixes
- 🟢 Low - Minor updates, nice-to-have

---

## Testing Checklist Template

Run after EACH component update:

```bash
# 1. Pod health
kubectl get pods -A | grep -v Running | grep -v Completed

# 2. Application sync status (if ArgoCD-managed)
kubectl get applications -n argocd

# 3. Certificate validity (after cert-manager)
kubectl get certificates -A | grep False

# 4. External secrets sync (after ESO)
kubectl get externalsecrets -A | grep SecretSyncedError

# 5. Load balancer IPs (after MetalLB)
kubectl get svc -A | grep LoadBalancer

# 6. Prometheus targets (after monitoring updates)
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
# Visit http://localhost:9090/targets

# 7. Vault health (after Vault update)
kubectl exec -n vault vault-0 -- vault status

# 8. Storage provisioning (after Longhorn)
kubectl get pvc -A | grep -v Bound

# 9. Component-specific logs
kubectl logs -n <namespace> <pod> | grep -i error
```

---

## Rollback Procedures

### Ansible-Managed Components
```bash
# 1. Revert chart_version in ansible/roles/k3sup/tasks/<component>.yml
# 2. Run playbook
ansible-playbook -i inventory/hosts.yml k3s-playbook.yml --tags <component>
```

### ArgoCD-Managed Components
```bash
# Option 1: Git revert
git revert <commit-hash>
git push

# Option 2: ArgoCD rollback
argocd app rollback <app-name> <revision-number>
```

### Nuclear Option
```bash
# Restore from Velero backup
velero restore create --from-backup <backup-name>
```

---

## Success Criteria

Each component upgrade is considered successful when:

1. ✅ Component deployed successfully
2. ✅ All pods are Running/Completed
3. ✅ Component-specific health checks pass
4. ✅ Dependent services remain healthy
5. ✅ No errors in component logs for 24 hours
6. ✅ Integration tests pass (where applicable)

---

## Notes & Decisions

### 2025-11-01
- Initial plan created
- Started with cert-manager as first high-priority update
- Branching strategy: One branch per component
- Will monitor each component for 24-48 hours before proceeding

### Valkey Decision Pending
- Need to decide on Bitnami subscription vs migration by Dec 2025
- Research alternatives if migrating

---

## Timeline

| Week | Phase | Components |
|------|-------|------------|
| 1 | Foundation | Ansible collections, cert-manager, ESO, MetalLB |
| 2 | Core Infrastructure | ArgoCD, Prometheus CRDs, Longhorn |
| 3 | Observability | kube-prometheus-stack, Loki, Grafana |
| 4 | Core Services | Vault, CNPG, Valkey decision |
| 5 | Auth & Apps | Authentik, Argo Workflows, Windmill |
| 6 | Network & Backup | Traefik, Velero |
| 7 | Buffer | Testing, documentation, cleanup |

**Target Completion:** Week 7
**Current Week:** Week 1
