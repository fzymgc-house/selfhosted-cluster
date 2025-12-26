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
k8s-login.sh admin    # or: developer, viewer

# 3. Use kubectl
kubectl get nodes
```

> **Note:** The `scripts/` directory is in PATH via `.envrc`. Run `direnv allow` if prompted.

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

> **⚠️ WARNING**: Only use when Vault/Authentik are unavailable and emergency action is required.
> All break-glass usage should be documented and reviewed.

For emergency access when normal authentication fails:

```bash
export KUBECONFIG=~/.kube/configs/fzymgc-house-admin.yml
kubectl get nodes
```

**Important:**
- This bypasses all identity-based access controls
- Actions are not tied to your identity in audit logs
- Return to normal authentication as soon as possible
- Document the incident and reason for break-glass access
