# Kubernetes Vault PKI Access Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable identity-based kubectl access via Vault-issued short-lived client certificates, authenticated through Authentik SSO.

**Architecture:** Users authenticate to Vault via OIDC (Authentik), then request certificates from Vault PKI based on their group membership. Kubernetes validates certificates against the cluster CA and maps cert Organization field to RBAC groups.

**Tech Stack:** Terraform (Vault provider, Kubernetes provider, Authentik provider), Bash scripting

**Design Document:** `docs/plans/2025-12-26-k8s-oidc-access-design.md`

---

## Phase 1: Authentik Groups

### Task 1.1: Create Kubernetes Access Groups in Authentik

**Files:**
- Create: `tf/authentik/kubernetes-groups.tf`

**Step 1: Create the groups file**

```hcl
# tf/authentik/kubernetes-groups.tf
# Authentik groups for Kubernetes access tiers

resource "authentik_group" "k8s_admins" {
  name         = "k8s-admins"
  is_superuser = false
}

resource "authentik_group" "k8s_developers" {
  name         = "k8s-developers"
  is_superuser = false
}

resource "authentik_group" "k8s_viewers" {
  name         = "k8s-viewers"
  is_superuser = false
}
```

**Step 2: Validate Terraform configuration**

```bash
cd tf/authentik
terraform validate
```

Expected: `Success! The configuration is valid.`

**Step 3: Plan and verify changes**

```bash
terraform plan -out=tfplan
```

Expected: `Plan: 3 to add, 0 to change, 0 to destroy.`

**Step 4: Apply changes**

```bash
terraform apply tfplan
```

Expected: `Apply complete! Resources: 3 added`

**Step 5: Commit**

```bash
git add tf/authentik/kubernetes-groups.tf
git commit -m "feat(authentik): add k8s access groups"
```

---

## Phase 2: Vault PKI Roles

### Task 2.1: Create PKI Roles for K8s Client Certificates

**Files:**
- Create: `tf/vault/pki-k8s-roles.tf`

**Reference:** Pattern from `tf/vault/pki-router-hosts.tf`

**Step 1: Create the PKI roles file**

```hcl
# tf/vault/pki-k8s-roles.tf
# PKI roles for Kubernetes client certificate issuance.
# Each role has a fixed Organization field that maps to K8s RBAC groups.

# =============================================================================
# Admin Role - Full cluster access
# =============================================================================

resource "vault_pki_secret_backend_role" "k8s_admin" {
  backend = "fzymgc-house/v1/ica1/v1"
  name    = "k8s-admin"

  # Allowed subject names - users authenticate as user@fzymgc.house
  allowed_domains    = ["fzymgc.house"]
  allow_bare_domains = true
  allow_subdomains   = false

  # Extended Key Usage: clientAuth only
  server_flag = false
  client_flag = true

  # Key configuration: ECDSA P-256
  key_type = "ec"
  key_bits = 256

  # Certificate TTL: 8 hours default, 24 hours max
  ttl     = "8h"
  max_ttl = "24h"

  # Fixed organization - maps to K8s group
  organization = ["k8s-admins"]

  # Disable hostname enforcement for client certs
  allow_any_name    = false
  enforce_hostnames = false
}

# =============================================================================
# Developer Role - Read/write workloads
# =============================================================================

resource "vault_pki_secret_backend_role" "k8s_developer" {
  backend = "fzymgc-house/v1/ica1/v1"
  name    = "k8s-developer"

  allowed_domains    = ["fzymgc.house"]
  allow_bare_domains = true
  allow_subdomains   = false

  server_flag = false
  client_flag = true

  key_type = "ec"
  key_bits = 256

  ttl     = "8h"
  max_ttl = "24h"

  organization = ["k8s-developers"]

  allow_any_name    = false
  enforce_hostnames = false
}

# =============================================================================
# Viewer Role - Read-only access
# =============================================================================

resource "vault_pki_secret_backend_role" "k8s_viewer" {
  backend = "fzymgc-house/v1/ica1/v1"
  name    = "k8s-viewer"

  allowed_domains    = ["fzymgc.house"]
  allow_bare_domains = true
  allow_subdomains   = false

  server_flag = false
  client_flag = true

  key_type = "ec"
  key_bits = 256

  ttl     = "8h"
  max_ttl = "24h"

  organization = ["k8s-viewers"]

  allow_any_name    = false
  enforce_hostnames = false
}
```

**Step 2: Validate Terraform configuration**

```bash
cd tf/vault
terraform validate
```

Expected: `Success! The configuration is valid.`

**Step 3: Plan and verify changes**

```bash
terraform plan -out=tfplan
```

Expected: `Plan: 3 to add, 0 to change, 0 to destroy.`

**Step 4: Apply changes**

```bash
terraform apply tfplan
```

Expected: `Apply complete! Resources: 3 added`

**Step 5: Verify roles exist in Vault**

```bash
vault list fzymgc-house/v1/ica1/v1/roles
```

Expected output should include: `k8s-admin`, `k8s-developer`, `k8s-viewer`

**Step 6: Commit**

```bash
git add tf/vault/pki-k8s-roles.tf
git commit -m "feat(vault): add PKI roles for k8s client certs"
```

---

## Phase 3: Vault Policies

### Task 3.1: Create Policies for Certificate Issuance

**Files:**
- Create: `tf/vault/policy-k8s-access.tf`

**Step 1: Create the policies file**

```hcl
# tf/vault/policy-k8s-access.tf
# Vault policies controlling which K8s PKI roles users can access.
# Each policy corresponds to an Authentik group.

# =============================================================================
# Admin Policy - Can issue all cert types
# =============================================================================

resource "vault_policy" "k8s_admin_cert" {
  name = "k8s-admin-cert"

  policy = <<-EOT
    # K8s admin can issue admin, developer, and viewer certs
    path "fzymgc-house/v1/ica1/v1/issue/k8s-admin" {
      capabilities = ["create", "update"]
    }
    path "fzymgc-house/v1/ica1/v1/issue/k8s-developer" {
      capabilities = ["create", "update"]
    }
    path "fzymgc-house/v1/ica1/v1/issue/k8s-viewer" {
      capabilities = ["create", "update"]
    }
    # Read CA chain for kubeconfig
    path "fzymgc-house/v1/ica1/v1/ca_chain" {
      capabilities = ["read"]
    }
  EOT
}

# =============================================================================
# Developer Policy - Can issue developer and viewer certs
# =============================================================================

resource "vault_policy" "k8s_developer_cert" {
  name = "k8s-developer-cert"

  policy = <<-EOT
    # K8s developer can issue developer and viewer certs
    path "fzymgc-house/v1/ica1/v1/issue/k8s-developer" {
      capabilities = ["create", "update"]
    }
    path "fzymgc-house/v1/ica1/v1/issue/k8s-viewer" {
      capabilities = ["create", "update"]
    }
    # Read CA chain for kubeconfig
    path "fzymgc-house/v1/ica1/v1/ca_chain" {
      capabilities = ["read"]
    }
  EOT
}

# =============================================================================
# Viewer Policy - Can only issue viewer certs
# =============================================================================

resource "vault_policy" "k8s_viewer_cert" {
  name = "k8s-viewer-cert"

  policy = <<-EOT
    # K8s viewer can only issue viewer certs
    path "fzymgc-house/v1/ica1/v1/issue/k8s-viewer" {
      capabilities = ["create", "update"]
    }
    # Read CA chain for kubeconfig
    path "fzymgc-house/v1/ica1/v1/ca_chain" {
      capabilities = ["read"]
    }
  EOT
}
```

**Step 2: Validate and plan**

```bash
cd tf/vault
terraform validate && terraform plan -out=tfplan
```

Expected: `Plan: 3 to add`

**Step 3: Apply changes**

```bash
terraform apply tfplan
```

**Step 4: Verify policies exist**

```bash
vault policy list | rg k8s
```

Expected: `k8s-admin-cert`, `k8s-developer-cert`, `k8s-viewer-cert`

**Step 5: Commit**

```bash
git add tf/vault/policy-k8s-access.tf
git commit -m "feat(vault): add policies for k8s cert issuance"
```

---

## Phase 4: OIDC Group Mapping

### Task 4.1: Create Vault Identity Groups for K8s Access

**Files:**
- Modify: `tf/vault/groups-and-roles.tf`

**Step 1: Add K8s identity groups to existing file**

Append to `tf/vault/groups-and-roles.tf`:

```hcl
# =============================================================================
# Kubernetes Access Groups
# =============================================================================
# External groups that map to Authentik groups via OIDC.
# When users authenticate via OIDC with these Authentik groups,
# they receive the corresponding Vault policies.

resource "vault_identity_group" "k8s_admins" {
  name     = "k8s-admins"
  type     = "external"
  policies = [vault_policy.k8s_admin_cert.name]
}

resource "vault_identity_group" "k8s_developers" {
  name     = "k8s-developers"
  type     = "external"
  policies = [vault_policy.k8s_developer_cert.name]
}

resource "vault_identity_group" "k8s_viewers" {
  name     = "k8s-viewers"
  type     = "external"
  policies = [vault_policy.k8s_viewer_cert.name]
}
```

**Step 2: Validate and plan**

```bash
terraform validate && terraform plan -out=tfplan
```

Expected: `Plan: 3 to add`

**Step 3: Apply changes**

```bash
terraform apply tfplan
```

**Step 4: Commit**

```bash
git add tf/vault/groups-and-roles.tf
git commit -m "feat(vault): add identity groups for k8s access"
```

### Task 4.2: Create OIDC Group Aliases

**Files:**
- Create: `tf/vault/oidc-k8s-group-aliases.tf`

**Note:** This maps Authentik group names to Vault identity groups via the OIDC auth backend.

**Step 1: Check existing OIDC auth accessor**

```bash
vault auth list -format=json | jq -r '.["oidc/"].accessor'
```

Save this accessor ID for the next step.

**Step 2: Create the group aliases file**

```hcl
# tf/vault/oidc-k8s-group-aliases.tf
# Map Authentik group claims to Vault identity groups

data "vault_auth_backend" "oidc" {
  path = "oidc"
}

resource "vault_identity_group_alias" "k8s_admins" {
  name           = "k8s-admins"
  mount_accessor = data.vault_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.k8s_admins.id
}

resource "vault_identity_group_alias" "k8s_developers" {
  name           = "k8s-developers"
  mount_accessor = data.vault_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.k8s_developers.id
}

resource "vault_identity_group_alias" "k8s_viewers" {
  name           = "k8s-viewers"
  mount_accessor = data.vault_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.k8s_viewers.id
}
```

**Step 3: Validate and plan**

```bash
terraform validate && terraform plan -out=tfplan
```

Expected: `Plan: 3 to add`

**Step 4: Apply changes**

```bash
terraform apply tfplan
```

**Step 5: Commit**

```bash
git add tf/vault/oidc-k8s-group-aliases.tf
git commit -m "feat(vault): add OIDC group aliases for k8s access"
```

---

## Phase 5: Kubernetes RBAC

### Task 5.1: Create ClusterRoleBindings for Cert-Based Groups

**Files:**
- Create: `tf/vault/k8s-rbac-vault-certs.tf`

**Step 1: Create the RBAC file**

```hcl
# tf/vault/k8s-rbac-vault-certs.tf
# Kubernetes RBAC bindings for Vault-issued certificate groups.
# Maps certificate Organization field to ClusterRoles.

resource "kubernetes_cluster_role_binding" "vault_cert_admins" {
  metadata {
    name = "vault-cert-cluster-admins"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "rbac"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "Group"
    name      = "k8s-admins"
    api_group = "rbac.authorization.k8s.io"
  }
}

resource "kubernetes_cluster_role_binding" "vault_cert_developers" {
  metadata {
    name = "vault-cert-developers"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "rbac"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "edit"
  }

  subject {
    kind      = "Group"
    name      = "k8s-developers"
    api_group = "rbac.authorization.k8s.io"
  }
}

resource "kubernetes_cluster_role_binding" "vault_cert_viewers" {
  metadata {
    name = "vault-cert-viewers"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "rbac"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "view"
  }

  subject {
    kind      = "Group"
    name      = "k8s-viewers"
    api_group = "rbac.authorization.k8s.io"
  }
}
```

**Step 2: Validate and plan**

```bash
terraform validate && terraform plan -out=tfplan
```

Expected: `Plan: 3 to add`

**Step 3: Apply changes**

```bash
terraform apply tfplan
```

**Step 4: Verify ClusterRoleBindings exist**

```bash
kubectl get clusterrolebindings | rg vault-cert
```

Expected: `vault-cert-cluster-admins`, `vault-cert-developers`, `vault-cert-viewers`

**Step 5: Commit**

```bash
git add tf/vault/k8s-rbac-vault-certs.tf
git commit -m "feat(vault): add k8s RBAC for vault cert groups"
```

---

## Phase 6: Helper Script

### Task 6.1: Create k8s-login.sh Helper Script

**Files:**
- Create: `scripts/k8s-login.sh`

**Step 1: Create scripts directory if needed**

```bash
mkdir -p scripts
```

**Step 2: Create the helper script**

```bash
#!/usr/bin/env bash
# k8s-login.sh - Authenticate to Kubernetes using Vault-issued certificates
#
# Usage: k8s-login.sh [admin|developer|viewer]
#
# Prerequisites:
#   - vault CLI installed and in PATH
#   - kubectl CLI installed and in PATH
#   - jq installed and in PATH
#   - Authenticated to Vault: vault login -method=oidc

set -euo pipefail

ROLE="${1:-viewer}"
CLUSTER="fzymgc-house"
API_SERVER="https://192.168.20.140:6443"
VAULT_PKI_PATH="fzymgc-house/v1/ica1/v1"
TTL="${K8S_CERT_TTL:-8h}"

# Validate role
case "$ROLE" in
  admin|developer|viewer) ;;
  *)
    echo "Usage: k8s-login [admin|developer|viewer]"
    echo ""
    echo "Roles:"
    echo "  admin     - Full cluster-admin access"
    echo "  developer - Read/write workloads (edit role)"
    echo "  viewer    - Read-only access (view role)"
    exit 1
    ;;
esac

# Check prerequisites
command -v vault >/dev/null 2>&1 || { echo "Error: vault CLI not found"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl CLI not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq not found"; exit 1; }

# Check Vault authentication
if ! vault token lookup >/dev/null 2>&1; then
  echo "Error: Not authenticated to Vault"
  echo "Run: vault login -method=oidc"
  exit 1
fi

# Get username from current Vault token
USERNAME=$(vault token lookup -format=json | jq -r '.data.display_name // .data.entity_id')

echo "Requesting $ROLE certificate for $USERNAME (TTL: $TTL)..."

# Issue certificate from Vault
CERT_DATA=$(vault write -format=json "$VAULT_PKI_PATH/issue/k8s-$ROLE" \
  common_name="$USERNAME" \
  ttl="$TTL")

# Extract cert, key, and CA
CLIENT_CERT=$(echo "$CERT_DATA" | jq -r '.data.certificate')
CLIENT_KEY=$(echo "$CERT_DATA" | jq -r '.data.private_key')
CA_CHAIN=$(echo "$CERT_DATA" | jq -r '.data.ca_chain[0]')

# Create temp files for kubectl (process substitution doesn't work with --embed-certs)
CERT_FILE=$(mktemp)
KEY_FILE=$(mktemp)
CA_FILE=$(mktemp)
trap "rm -f $CERT_FILE $KEY_FILE $CA_FILE" EXIT

echo "$CLIENT_CERT" > "$CERT_FILE"
echo "$CLIENT_KEY" > "$KEY_FILE"
echo "$CA_CHAIN" > "$CA_FILE"

# Update kubeconfig
kubectl config set-cluster "$CLUSTER" \
  --server="$API_SERVER" \
  --certificate-authority="$CA_FILE" \
  --embed-certs=true

kubectl config set-credentials "$CLUSTER-$ROLE" \
  --client-certificate="$CERT_FILE" \
  --client-key="$KEY_FILE" \
  --embed-certs=true

kubectl config set-context "$CLUSTER-$ROLE" \
  --cluster="$CLUSTER" \
  --user="$CLUSTER-$ROLE"

kubectl config use-context "$CLUSTER-$ROLE"

echo "✓ Configured context: $CLUSTER-$ROLE (expires in $TTL)"
echo ""
echo "Test with: kubectl get nodes"
```

**Step 3: Make script executable**

```bash
chmod +x scripts/k8s-login.sh
```

**Step 4: Commit**

```bash
git add scripts/k8s-login.sh
git commit -m "feat: add k8s-login.sh helper script"
```

---

## Phase 7: Documentation

### Task 7.1: Create User Guide

**Files:**
- Create: `docs/kubernetes-access.md`

**Step 1: Create the documentation**

```markdown
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
```

**Step 2: Commit**

```bash
git add docs/kubernetes-access.md
git commit -m "docs: add kubernetes access user guide"
```

---

## Phase 8: Testing

### Task 8.1: End-to-End Test

**Step 1: Add yourself to k8s-admins group in Authentik**

Via Authentik admin UI: Users → [Your user] → Groups → Add to `k8s-admins`

**Step 2: Test Vault OIDC login**

```bash
vault login -method=oidc
```

Expected: Browser opens, authenticate via Authentik, success message.

**Step 3: Verify group membership in token**

```bash
vault token lookup -format=json | jq '.data.identity_policies'
```

Expected: Should include `k8s-admin-cert`

**Step 4: Test certificate issuance**

```bash
vault write fzymgc-house/v1/ica1/v1/issue/k8s-admin \
  common_name="test@fzymgc.house" \
  ttl="1h"
```

Expected: Returns certificate, private_key, ca_chain

**Step 5: Test helper script**

```bash
./scripts/k8s-login.sh admin
```

Expected: `✓ Configured context: fzymgc-house-admin`

**Step 6: Test kubectl access**

```bash
kubectl get nodes
```

Expected: List of cluster nodes

**Step 7: Test RBAC enforcement**

As viewer, try to create a pod (should fail):

```bash
./scripts/k8s-login.sh viewer
kubectl run test --image=nginx
```

Expected: `Error from server (Forbidden)`

**Step 8: Final commit**

```bash
git add -A
git commit -m "feat: complete k8s vault pki access implementation"
```

---

## Verification Checklist

- [ ] Authentik groups created (k8s-admins, k8s-developers, k8s-viewers)
- [ ] Vault PKI roles created (k8s-admin, k8s-developer, k8s-viewer)
- [ ] Vault policies created (k8s-admin-cert, k8s-developer-cert, k8s-viewer-cert)
- [ ] Vault identity groups created and mapped to OIDC
- [ ] K8s ClusterRoleBindings created
- [ ] Helper script works
- [ ] Documentation complete
- [ ] RBAC enforcement verified
