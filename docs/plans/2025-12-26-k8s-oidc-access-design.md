# Kubernetes Vault PKI Access Design

**Date:** 2025-12-26
**Status:** Approved
**Goal:** Enable identity-based kubectl access via Vault-issued short-lived client certificates, authenticated through Authentik SSO.

## Overview

Use Vault PKI to issue short-lived client certificates for kubectl access. Users authenticate to Vault via OIDC (Authentik SSO), then request certificates based on their group membership. Existing certificate-based access remains for break-glass scenarios and automation.

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│    User     │────▶│   Vault     │────▶│  Authentik  │────▶│   Vault     │
│  (terminal) │     │  OIDC Auth  │     │  (SSO)      │     │  PKI Issue  │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                                                                   │
                                                          Client Cert
                                                                   │
                                                                   ▼
                                                            ┌─────────────┐
                                                            │  k3s API    │
                                                            │ (validates) │
                                                            └─────────────┘
```

### Authentication Flow

1. User runs `vault login -method=oidc` → browser opens to Authentik
2. Authentik authenticates, returns token to Vault with group claims
3. Vault maps groups to policies (e.g., `k8s-admins` → can issue admin certs)
4. User runs `k8s-login.sh admin` → Vault issues short-lived client cert
5. Helper script updates kubeconfig with new cert
6. kubectl uses cert → k3s validates against cluster CA

### Key Advantage

Zero changes to k3s API server. Certificate authentication already works.

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Authentik groups | `tf/authentik` | k8s-admins, k8s-developers, k8s-viewers |
| Vault PKI roles | `tf/vault` | Issue certs with fixed Organization field |
| Vault policies | `tf/vault` | Control which roles each group can access |
| K8s RBAC | `tf/vault` | Map cert Organization to K8s permissions |
| Helper script | `scripts/` | Automate cert request + kubeconfig update |

## Vault PKI Configuration

### PKI Mount Path

```
fzymgc-house/v1/ica1/v1/
```

### PKI Roles

One role per access tier, with fixed Organization field:

```hcl
resource "vault_pki_secret_backend_role" "k8s_admin" {
  backend           = "fzymgc-house/v1/ica1/v1"
  name              = "k8s-admin"
  ttl               = "8h"
  max_ttl           = "24h"
  allowed_domains   = ["fzymgc.house"]
  allow_subdomains  = false
  allow_any_name    = false
  enforce_hostnames = false
  key_usage         = ["DigitalSignature", "KeyEncipherment"]
  ext_key_usage     = ["ClientAuth"]
  organization      = ["k8s-admins"]  # Fixed - user cannot override
}

resource "vault_pki_secret_backend_role" "k8s_developer" {
  # ... same config ...
  name         = "k8s-developer"
  organization = ["k8s-developers"]
}

resource "vault_pki_secret_backend_role" "k8s_viewer" {
  # ... same config ...
  name         = "k8s-viewer"
  organization = ["k8s-viewers"]
}
```

### Certificate to Kubernetes Identity Mapping

| Cert Field | K8s Mapping | Example |
|------------|-------------|---------|
| `CN` (Common Name) | Username | `alice@fzymgc.house` |
| `O` (Organization) | Groups | `k8s-admins` |

Multiple groups supported via multiple `O=` entries in cert.

## Vault Policies

### Policy Structure

```hcl
# Policy: k8s-admin-cert (for k8s-admins group)
path "fzymgc-house/v1/ica1/v1/issue/k8s-admin" {
  capabilities = ["create", "update"]
}
path "fzymgc-house/v1/ica1/v1/issue/k8s-developer" {
  capabilities = ["create", "update"]
}
path "fzymgc-house/v1/ica1/v1/issue/k8s-viewer" {
  capabilities = ["create", "update"]
}

# Policy: k8s-dev-cert (for k8s-developers group)
path "fzymgc-house/v1/ica1/v1/issue/k8s-developer" {
  capabilities = ["create", "update"]
}
path "fzymgc-house/v1/ica1/v1/issue/k8s-viewer" {
  capabilities = ["create", "update"]
}

# Policy: k8s-viewer-cert (for k8s-viewers group)
path "fzymgc-house/v1/ica1/v1/issue/k8s-viewer" {
  capabilities = ["create", "update"]
}
```

### Authentik Group → Vault Policy Mapping

| Authentik Group | Vault Policy | Can Issue |
|-----------------|--------------|-----------|
| `k8s-admins` | `k8s-admin-cert` | admin, developer, viewer certs |
| `k8s-developers` | `k8s-dev-cert` | developer, viewer certs |
| `k8s-viewers` | `k8s-viewer-cert` | viewer certs only |

## Kubernetes RBAC

### ClusterRoleBindings

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-cert-cluster-admins
subjects:
  - kind: Group
    name: k8s-admins
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-cert-developers
subjects:
  - kind: Group
    name: k8s-developers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: edit
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-cert-viewers
subjects:
  - kind: Group
    name: k8s-viewers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io
```

### Role Mapping Summary

| Cert Organization | K8s Group | ClusterRole | Access |
|-------------------|-----------|-------------|--------|
| `k8s-admins` | `k8s-admins` | `cluster-admin` | Full access |
| `k8s-developers` | `k8s-developers` | `edit` | Read/write workloads |
| `k8s-viewers` | `k8s-viewers` | `view` | Read-only |

**Managed in:** `tf/vault/k8s-rbac-vault-certs.tf`

## Authentication Hierarchy

All methods work simultaneously:

| Method | Use Case | Token Lifetime |
|--------|----------|----------------|
| Static client certificates | Break-glass, automation, Windmill | Long-lived (1 year) |
| Vault-issued certificates | Daily human access | Short-lived (8 hours) |
| Service accounts | In-cluster pods | Configurable |

### Break-Glass Protocol

The existing `fzymgc-house-admin.yml` kubeconfig remains valid. Store securely in:
1. Vault at `secret/fzymgc-house/cluster/break-glass/kubeconfig`
2. Offline backup (encrypted USB, password manager)

## Helper Script

**Location:** `scripts/k8s-login.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-viewer}"
CLUSTER="fzymgc-house"
API_SERVER="https://192.168.20.140:6443"
VAULT_PKI_PATH="fzymgc-house/v1/ica1/v1"
TTL="${K8S_CERT_TTL:-8h}"
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"

# Validate role
case "$ROLE" in
  admin|developer|viewer) ;;
  *) echo "Usage: k8s-login [admin|developer|viewer]"; exit 1 ;;
esac

# Get username from current Vault token
USERNAME=$(vault token lookup -format=json | jq -r '.data.display_name // .data.entity_id')

echo "Requesting $ROLE certificate for $USERNAME (TTL: $TTL)..."

# Issue certificate from Vault
CERT_DATA=$(vault write -format=json "$VAULT_PKI_PATH/issue/k8s-$ROLE" \
  common_name="$USERNAME" \
  ttl="$TTL")

# Extract cert and key
CLIENT_CERT=$(echo "$CERT_DATA" | jq -r '.data.certificate')
CLIENT_KEY=$(echo "$CERT_DATA" | jq -r '.data.private_key')
CA_CHAIN=$(echo "$CERT_DATA" | jq -r '.data.ca_chain[0]')

# Update kubeconfig
kubectl config set-cluster "$CLUSTER" \
  --server="$API_SERVER" \
  --certificate-authority=<(echo "$CA_CHAIN") \
  --embed-certs=true

kubectl config set-credentials "$CLUSTER-$ROLE" \
  --client-certificate=<(echo "$CLIENT_CERT") \
  --client-key=<(echo "$CLIENT_KEY") \
  --embed-certs=true

kubectl config set-context "$CLUSTER-$ROLE" \
  --cluster="$CLUSTER" \
  --user="$CLUSTER-$ROLE"

kubectl config use-context "$CLUSTER-$ROLE"

echo "✓ Configured context: $CLUSTER-$ROLE (expires in $TTL)"
```

### User Experience

```bash
$ vault login -method=oidc
# Browser opens → Authentik SSO → success

$ k8s-login admin
Requesting admin certificate for alice@fzymgc.house (TTL: 8h)...
✓ Configured context: fzymgc-house-admin (expires in 8h)

$ kubectl get nodes
NAME           STATUS   ROLES                  AGE
tpi-alpha-1    Ready    control-plane,master   204d
...
```

## Implementation Plan

### Deployment Order

| Phase | Component | Location | Notes |
|-------|-----------|----------|-------|
| 1 | Authentik groups | `tf/authentik` | Create k8s-admins, k8s-developers, k8s-viewers |
| 2 | PKI roles | `tf/vault` | k8s-admin, k8s-developer, k8s-viewer roles |
| 3 | Vault policies | `tf/vault` | Control who can issue which certs |
| 4 | OIDC group mapping | `tf/vault` | Map Authentik groups to Vault policies |
| 5 | K8s RBAC | `tf/vault` | ClusterRoleBindings for cert groups |
| 6 | Helper script | `scripts/` | k8s-login.sh for user convenience |
| 7 | Documentation | `docs/` | User guide for k8s access |

### File Changes

```
tf/authentik/
└── kubernetes-groups.tf           # New: k8s-admins, k8s-developers, k8s-viewers

tf/vault/
├── pki-k8s-roles.tf               # New: PKI roles for k8s client certs
├── policy-k8s-access.tf           # New: Policies for cert issuance
├── k8s-rbac-vault-certs.tf        # New: ClusterRoleBindings
└── groups-and-roles.tf            # Modify: Add OIDC group → policy mappings

scripts/
└── k8s-login.sh                   # New: Helper script

docs/
└── kubernetes-access.md           # New: User guide
```

### Testing Plan

1. Create test user in each Authentik group
2. `vault login -method=oidc` as each user
3. Verify correct PKI role access (admin can issue admin, dev cannot)
4. Run `k8s-login.sh` and verify kubectl works
5. Confirm RBAC limits access appropriately
