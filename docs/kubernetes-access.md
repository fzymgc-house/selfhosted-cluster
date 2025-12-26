# Kubernetes Access Guide

This guide explains how to authenticate to the fzymgc-house Kubernetes cluster using Vault-issued certificates.

## Prerequisites

- `vault` CLI installed
- `kubectl` CLI installed
- `jq` installed
- Member of one of: `k8s-admins`, `k8s-developers`, `k8s-viewers` in Authentik

## Quick Start

```bash
# 1. Authenticate to Vault via Authentik SSO
vault login -method=oidc

# 2. Get a Kubernetes certificate and configure kubectl
./scripts/k8s-login.sh admin    # or: developer, viewer

# 3. Use kubectl
kubectl get nodes
```

## Access Levels

| Role | ClusterRole | Capabilities |
|------|-------------|--------------|
| `admin` | `cluster-admin` | Full cluster access |
| `developer` | `edit` | Create/modify workloads, no RBAC changes |
| `viewer` | `view` | Read-only access |

## Certificate Lifetime

- Default: 8 hours
- Maximum: 24 hours
- Override: `K8S_CERT_TTL=4h ./scripts/k8s-login.sh admin`

## Troubleshooting

### "Not authenticated to Vault"

Run `vault login -method=oidc` first.

### "Permission denied" when issuing certificate

Your Authentik group doesn't have access to that role level:
- `k8s-admins` can issue: admin, developer, viewer
- `k8s-developers` can issue: developer, viewer
- `k8s-viewers` can issue: viewer only

### Certificate expired

Re-run `./scripts/k8s-login.sh <role>` to get a fresh certificate.

## Break-Glass Access

For emergency access when Vault/Authentik are unavailable, use the static admin kubeconfig:

```bash
export KUBECONFIG=~/.kube/configs/fzymgc-house-admin.yml
kubectl get nodes
```

This should only be used for break-glass scenarios.
