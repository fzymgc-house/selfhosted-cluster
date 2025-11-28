# Authentik IaC Phase 1: Critical Infrastructure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Import Vault, ArgoCD, and Argo Workflows applications, providers, and groups into Terraform using terraform import to preserve existing configurations without service disruption.

**Architecture:** Each application gets its own .tf file containing groups, OAuth2 provider, application, and Vault secret storage. Import existing resources by UUID to maintain current client IDs, secrets, and configurations.

**Tech Stack:** Terraform 1.14+, Authentik provider v2024.12.1, Vault provider v4.8.0, Authentik API

---

## Task 1: Create Shared Data Sources

**Files:**
- Create: `tf/authentik/data-sources.tf`

**Step 1: Create data sources file**

Create `tf/authentik/data-sources.tf`:

```hcl
# Data sources shared across multiple applications
# These reference Authentik's default flows and resources

# Default authorization flow (implicit consent)
data "authentik_flow" "default_authorization_flow" {
  slug = "default-provider-authorization-implicit-consent"
}

# Default invalidation flow
data "authentik_flow" "default_invalidation_flow" {
  slug = "default-invalidation-flow"
}

# Default provider invalidation flow
data "authentik_flow" "default_provider_invalidation_flow" {
  slug = "default-provider-invalidation-flow"
}

# Default self-signed certificate for signing
data "authentik_certificate_key_pair" "generated" {
  name = "authentik Self-signed Certificate"
}

# Standard OAuth2 scope mappings
data "authentik_property_mapping_provider_scope" "email" {
  managed = "goauthentik.io/providers/oauth2/scope-email"
}

data "authentik_property_mapping_provider_scope" "openid" {
  managed = "goauthentik.io/providers/oauth2/scope-openid"
}

data "authentik_property_mapping_provider_scope" "profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

data "authentik_property_mapping_provider_scope" "groups" {
  managed = "goauthentik.io/providers/oauth2/scope-groups"
}
```

**Step 2: Validate Terraform configuration**

Run: `cd /Volumes/Code/github.com/fzymgc-house/selfhosted-cluster/.worktrees/authentik-iac-phase1/tf/authentik && terraform validate`

Expected: `Success! The configuration is valid.`

**Step 3: Commit**

```bash
cd /Volumes/Code/github.com/fzymgc-house/selfhosted-cluster/.worktrees/authentik-iac-phase1
git add tf/authentik/data-sources.tf
git commit -m "feat: Add shared Authentik data sources for IaC"
```

---

## Task 2: Import Vault Groups

**Files:**
- Create: `tf/authentik/vault.tf`

**Step 1: Create Vault groups**

Create `tf/authentik/vault.tf`:

```hcl
# Vault OAuth2/OIDC Integration
# Provides single sign-on for HashiCorp Vault

# Groups for Vault access control
resource "authentik_group" "vault_users" {
  name = "vault-users"
}

resource "authentik_group" "vault_admin" {
  name         = "vault-admin"
  parent       = authentik_group.vault_users.id
  is_superuser = false
}
```

**Step 2: Import vault_users group**

Run: `terraform import authentik_group.vault_users 899d2087-ebc2-40f0-9114-20c053897c5b`

Expected: `Import successful!`

**Step 3: Import vault_admin group**

Run: `terraform import authentik_group.vault_admin 9802524d-00a9-4692-af9c-6b1ba1bd040b`

Expected: `Import successful!`

**Step 4: Verify imports**

Run: `terraform plan`

Expected: `No changes. Your infrastructure matches the configuration.`

**Step 5: Commit**

```bash
git add tf/authentik/vault.tf
git commit -m "feat: Import Vault groups into Terraform"
```

---

## Task 3: Import Vault OAuth2 Provider

**Files:**
- Modify: `tf/authentik/vault.tf`

**Step 1: Add Vault OAuth2 provider**

Append to `tf/authentik/vault.tf`:

```hcl

# OAuth2 Provider for Vault
resource "authentik_provider_oauth2" "vault" {
  name      = "Provider for Vault"
  client_id = "IoC5Ul9TnUprBbgPw8LoE0Ivu1X4Pv5YI0q60Bxc"

  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_provider_invalidation_flow.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://vault.fzymgc.house/oidc/callback"
    },
    {
      matching_mode = "strict"
      url           = "https://vault.fzymgc.house/ui/vault/auth/oidc/oidc/callback"
    },
    {
      matching_mode = "strict"
      url           = "http://localhost:8250/oidc/callback"
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.groups.id
  ]

  signing_key = data.authentik_certificate_key_pair.generated.id
}
```

**Step 2: Import provider**

Run: `terraform import authentik_provider_oauth2.vault 4`

Expected: `Import successful!`

**Step 3: Verify import**

Run: `terraform plan`

Expected: `No changes. Your infrastructure matches the configuration.`

**Step 4: Commit**

```bash
git add tf/authentik/vault.tf
git commit -m "feat: Import Vault OAuth2 provider into Terraform"
```

---

## Task 4: Import Vault Application

**Files:**
- Modify: `tf/authentik/vault.tf`

**Step 1: Add Vault application**

Append to `tf/authentik/vault.tf`:

```hcl

# Vault Application
resource "authentik_application" "vault" {
  name              = "Vault"
  slug              = "vault"
  protocol_provider = authentik_provider_oauth2.vault.id
  meta_launch_url   = "https://vault.fzymgc.house"
  meta_icon         = "https://vault.fzymgc.house/ui/favicon-c02e22ca67f83a0fb6f2fd265074910a.png"
}
```

**Step 2: Import application**

Run: `terraform import authentik_application.vault 20008b75-b9a9-4ef7-8f87-341395025bc5`

Expected: `Import successful!`

**Step 3: Verify import**

Run: `terraform plan`

Expected: `No changes. Your infrastructure matches the configuration.`

**Step 4: Commit**

```bash
git add tf/authentik/vault.tf
git commit -m "feat: Import Vault application into Terraform"
```

---

## Task 5: Add Vault Credentials to Vault Secret Store

**Files:**
- Modify: `tf/authentik/vault.tf`

**Step 1: Add Vault secret storage**

Append to `tf/authentik/vault.tf`:

```hcl

# Store Vault OIDC credentials in Vault for cluster consumption
resource "vault_kv_secret_v2" "vault_oidc" {
  mount = "secret"
  name  = "fzymgc-house/cluster/vault/oidc"

  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.vault.client_id
    client_secret = authentik_provider_oauth2.vault.client_secret
  })
}
```

**Step 2: Apply Terraform to create Vault secret**

Run: `terraform apply -target=vault_kv_secret_v2.vault_oidc`

Expected: Plan shows 1 resource to add. Type `yes` to apply.

**Step 3: Verify creation**

Run: `vault kv get secret/fzymgc-house/cluster/vault/oidc`

Expected: Shows client_id and client_secret values

**Step 4: Commit**

```bash
git add tf/authentik/vault.tf
git commit -m "feat: Store Vault OIDC credentials in Vault"
```

---

## Task 6: Import ArgoCD Groups

**Files:**
- Create: `tf/authentik/argocd.tf`

**Step 1: Create ArgoCD groups**

Create `tf/authentik/argocd.tf`:

```hcl
# ArgoCD OAuth2/OIDC Integration
# Provides single sign-on for ArgoCD GitOps platform

# Groups for ArgoCD access control
resource "authentik_group" "argocd_user" {
  name = "argocd-user"
}

resource "authentik_group" "argocd_admin" {
  name = "argocd-admin"
}

resource "authentik_group" "cluster_admin" {
  name = "cluster-admin"
}
```

**Step 2: Import argocd_user group**

Run: `terraform import authentik_group.argocd_user 89401036-3a4a-49d9-a5fb-41dd6a13a409`

Expected: `Import successful!`

**Step 3: Import argocd_admin group**

Run: `terraform import authentik_group.argocd_admin 35ed6b4c-5fc4-42d2-a6ea-ce1f1ea8de15`

Expected: `Import successful!`

**Step 4: Import cluster_admin group**

Run: `terraform import authentik_group.cluster_admin 7d311e98-3a0e-47c8-9214-90fc6f96a012`

Expected: `Import successful!`

**Step 5: Verify imports**

Run: `terraform plan`

Expected: `No changes. Your infrastructure matches the configuration.`

**Step 6: Commit**

```bash
git add tf/authentik/argocd.tf
git commit -m "feat: Import ArgoCD groups into Terraform"
```

---

## Task 7: Import ArgoCD OAuth2 Provider

**Files:**
- Modify: `tf/authentik/argocd.tf`

**Step 1: Add ArgoCD OAuth2 provider**

Append to `tf/authentik/argocd.tf`:

```hcl

# OAuth2 Provider for ArgoCD
resource "authentik_provider_oauth2" "argocd" {
  name      = "Provider for ArgoCD"
  client_id = "iHIWDIIDroSBtFh2XbghfT0qUVKfklpt7P2iFN6l"

  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_provider_invalidation_flow.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://argocd.fzymgc.house/api/dex/callback"
    },
    {
      matching_mode = "strict"
      url           = "https://localhost:8085/auth/callback"
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id
  ]

  signing_key = data.authentik_certificate_key_pair.generated.id
}
```

**Step 2: Import provider**

Run: `terraform import authentik_provider_oauth2.argocd 18`

Expected: `Import successful!`

**Step 3: Verify import**

Run: `terraform plan`

Expected: `No changes. Your infrastructure matches the configuration.`

**Step 4: Commit**

```bash
git add tf/authentik/argocd.tf
git commit -m "feat: Import ArgoCD OAuth2 provider into Terraform"
```

---

## Task 8: Import ArgoCD Application

**Files:**
- Modify: `tf/authentik/argocd.tf`

**Step 1: Add ArgoCD application**

Append to `tf/authentik/argocd.tf`:

```hcl

# ArgoCD Application
resource "authentik_application" "argocd" {
  name              = "ArgoCD"
  slug              = "argo-cd"
  protocol_provider = authentik_provider_oauth2.argocd.id
  meta_launch_url   = "https://argocd.fzymgc.house"
}
```

**Step 2: Import application**

Run: `terraform import authentik_application.argocd a5276ada-8537-4de5-b436-af5046ea8f00`

Expected: `Import successful!`

**Step 3: Verify import**

Run: `terraform plan`

Expected: `No changes. Your infrastructure matches the configuration.`

**Step 4: Commit**

```bash
git add tf/authentik/argocd.tf
git commit -m "feat: Import ArgoCD application into Terraform"
```

---

## Task 9: Add ArgoCD Credentials to Vault Secret Store

**Files:**
- Modify: `tf/authentik/argocd.tf`

**Step 1: Add Vault secret storage**

Append to `tf/authentik/argocd.tf`:

```hcl

# Store ArgoCD OIDC credentials in Vault for cluster consumption
resource "vault_kv_secret_v2" "argocd_oidc" {
  mount = "secret"
  name  = "fzymgc-house/cluster/argocd/oidc"

  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.argocd.client_id
    client_secret = authentik_provider_oauth2.argocd.client_secret
  })
}
```

**Step 2: Apply Terraform to create Vault secret**

Run: `terraform apply -target=vault_kv_secret_v2.argocd_oidc`

Expected: Plan shows 1 resource to add. Type `yes` to apply.

**Step 3: Verify creation**

Run: `vault kv get secret/fzymgc-house/cluster/argocd/oidc`

Expected: Shows client_id and client_secret values

**Step 4: Commit**

```bash
git add tf/authentik/argocd.tf
git commit -m "feat: Store ArgoCD OIDC credentials in Vault"
```

---

## Task 10: Import Argo Workflows OAuth2 Provider and Application

**Files:**
- Create: `tf/authentik/argo-workflows.tf`

**Step 1: Create Argo Workflows file**

Create `tf/authentik/argo-workflows.tf`:

```hcl
# Argo Workflows OAuth2/OIDC Integration
# Provides single sign-on for Argo Workflows platform

# OAuth2 Provider for Argo Workflows
resource "authentik_provider_oauth2" "argo_workflows" {
  name      = "Provider for Argo Workflow"
  client_id = "3DgaUYpDvHyMuuXGiMVwZXOJzCmTxBeQydZYYF8Z"

  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_provider_invalidation_flow.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://argo-workflows.fzymgc.house/oauth2/callback"
    },
    {
      matching_mode = "strict"
      url           = "https://argoworkflows.fzymgc.house/oauth2/callback"
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id
  ]

  signing_key = data.authentik_certificate_key_pair.generated.id
}

# Argo Workflows Application
resource "authentik_application" "argo_workflows" {
  name              = "Argo Workflow"
  slug              = "argo-workflow"
  protocol_provider = authentik_provider_oauth2.argo_workflows.id
  meta_launch_url   = "https://argo-workflows.fzymgc.house"
}

# Store Argo Workflows OIDC credentials in Vault for cluster consumption
resource "vault_kv_secret_v2" "argo_workflows_oidc" {
  mount = "secret"
  name  = "fzymgc-house/cluster/argo-workflows/oidc"

  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.argo_workflows.client_id
    client_secret = authentik_provider_oauth2.argo_workflows.client_secret
  })
}
```

**Step 2: Import provider**

Run: `terraform import authentik_provider_oauth2.argo_workflows 51`

Expected: `Import successful!`

**Step 3: Import application**

Run: `terraform import authentik_application.argo_workflows dd21f1f8-b745-4f4a-96c9-bb8ef417d3fe`

Expected: `Import successful!`

**Step 4: Apply Terraform to create Vault secret**

Run: `terraform apply -target=vault_kv_secret_v2.argo_workflows_oidc`

Expected: Plan shows 1 resource to add. Type `yes` to apply.

**Step 5: Verify no unexpected changes**

Run: `terraform plan`

Expected: `No changes. Your infrastructure matches the configuration.`

**Step 6: Commit**

```bash
git add tf/authentik/argo-workflows.tf
git commit -m "feat: Import Argo Workflows OAuth2 integration into Terraform"
```

---

## Task 11: Final Validation

**Step 1: Run full terraform plan**

Run: `terraform plan`

Expected: `No changes. Your infrastructure matches the configuration.`

**Step 2: Verify Vault OIDC logins still work**

Test: Login to Vault at https://vault.fzymgc.house using OIDC

Expected: Login successful, no errors

**Step 3: Verify ArgoCD OIDC logins still work**

Test: Login to ArgoCD at https://argocd.fzymgc.house using SSO

Expected: Login successful, no errors

**Step 4: Verify Argo Workflows OIDC logins still work**

Test: Login to Argo Workflows at https://argo-workflows.fzymgc.house using SSO

Expected: Login successful, no errors

**Step 5: Commit validation notes**

```bash
echo "# Phase 1 Validation

All critical infrastructure imported successfully:
- Vault: OAuth2 provider, application, groups ✓
- ArgoCD: OAuth2 provider, application, groups ✓
- Argo Workflows: OAuth2 provider, application ✓

All OIDC logins tested and working.
terraform plan shows no changes.
" > VALIDATION.md

git add VALIDATION.md
git commit -m "docs: Add Phase 1 validation results"
```

---

## Success Criteria

- [ ] All 5 groups imported (vault-users, vault-admin, argocd-user, argocd-admin, cluster-admin)
- [ ] All 3 OAuth2 providers imported (Vault, ArgoCD, Argo Workflows)
- [ ] All 3 applications imported (Vault, ArgoCD, Argo Workflows)
- [ ] All 3 OIDC credential sets stored in Vault
- [ ] `terraform plan` shows "No changes"
- [ ] Vault OIDC login works
- [ ] ArgoCD SSO login works
- [ ] Argo Workflows SSO login works
- [ ] All changes committed to git

## Notes

- All commands assume working directory is `tf/authentik` unless otherwise specified
- UUIDs and client IDs are the actual production values from Authentik
- Terraform import preserves existing secrets - no regeneration
- Each commit is atomic and can be reviewed independently
