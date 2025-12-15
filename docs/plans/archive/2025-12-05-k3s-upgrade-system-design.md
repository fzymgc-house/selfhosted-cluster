# K3s Upgrade System Design

## Overview

Deploy the Rancher System Upgrade Controller (SUC) to enable declarative, GitOps-managed k3s upgrades. Initial upgrade from v1.32.5+k3s1 to v1.34.2+k3s1.

## Current State

- k3s v1.32.5+k3s1 on 4 nodes (3 control-plane, 1 worker)
- containerd 2.0.5
- No upgrade mechanism currently in place
- Cluster installed via k3sup/Ansible

## Target State

- k3s v1.34.2+k3s1
- System Upgrade Controller managing future upgrades
- Upgrade Plans version-controlled in git, synced via ArgoCD

## Architecture

### Components

```
argocd/app-configs/system-upgrade/
├── kustomization.yaml
├── namespace.yaml
├── controller.yaml      # SUC deployment + RBAC
├── plan-server.yaml     # Plan for control-plane nodes
└── plan-agent.yaml      # Plan for worker nodes
```

### ArgoCD Integration

- New application in `argocd/cluster-app/`
- Auto-sync enabled
- Sync waves:
  - Namespace: -100
  - Controller + RBAC: -100
  - Plans: -99

## Plan Configuration

### Server Plan (control-plane)

- Label selector: `node-role.kubernetes.io/control-plane=true`
- Concurrency: 1 (one node at a time)
- Cordon + drain before upgrade
- No dependencies (runs first)

### Agent Plan (workers)

- Label selector: nodes without control-plane role
- Concurrency: 1
- Cordon + drain before upgrade
- Depends on server plan completion

### Upgrade Trigger

All nodes upgrade automatically when Plan version changes. No opt-in labels required.

## Upgrade Process

1. Update version in `plan-server.yaml` and `plan-agent.yaml`
2. Commit and push to git
3. ArgoCD syncs the Plans
4. SUC upgrades control-plane nodes first (sequential)
5. SUC upgrades worker nodes after control-plane complete
6. Each node: cordon → drain → upgrade → uncordon

## Timing

- ~3-5 minutes per node
- Total: ~15-20 minutes for 4 nodes
- Control-plane nodes must complete before workers start

## Monitoring

```bash
# Watch plan progress
kubectl get plans -n system-upgrade -w

# Watch node versions
kubectl get nodes -w

# SUC logs
kubectl logs -n system-upgrade -l app=system-upgrade-controller -f
```

## Rollback

K3s has no built-in rollback. If upgrade fails:
1. Manually SSH to affected node
2. Run k3s installer with previous version
3. Restart k3s service

## References

- [K3s Automated Upgrades](https://docs.k3s.io/upgrades/automated)
- [System Upgrade Controller](https://github.com/rancher/system-upgrade-controller)
- [K3s Releases](https://github.com/k3s-io/k3s/releases)
- Issue #97: Teleport PostgreSQL backend requires k8s 1.33+ for ImageVolume
