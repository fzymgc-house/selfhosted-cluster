# Grafana OIDC Integration - Phase 2a Design

**Date:** 2025-11-28
**Phase:** 2a of Authentik IaC Migration
**Status:** Design Complete

## Overview

Import Grafana OAuth2 provider, application, and groups into Terraform following the proven Phase 1 pattern. This brings Grafana authentication under Infrastructure as Code management with zero service disruption.

## Scope

**Resources to Import:**
- **Groups:** `grafana-admin`, `grafana-editor` (two-tier hierarchy)
- **OAuth2 Provider:** Existing Grafana OIDC provider in Authentik
- **Application:** Grafana application in Authentik
- **Vault Credentials:** Store client_id and client_secret at `secret/fzymgc-house/cluster/grafana/oidc`

**Out of Scope:**
- Grafana configuration changes
- User/group membership modifications
- Flow or certificate changes

## Architecture

### File Structure

```
tf/authentik/
├── data-sources.tf        # Shared data sources (existing)
├── grafana.tf             # NEW: Grafana OIDC integration
├── vault.tf               # Existing
├── argocd.tf              # Existing
├── argo-workflows.tf      # Existing
└── mealie.tf              # Existing
```

### Resource Dependencies

```
authentik_group.grafana_editor (parent)
  └── authentik_group.grafana_admin (child)

authentik_provider_oauth2.grafana
  ├── depends on: data.authentik_flow.*
  ├── depends on: data.authentik_certificate_key_pair.*
  └── depends on: data.authentik_property_mapping_provider_scope.*

authentik_application.grafana
  └── depends on: authentik_provider_oauth2.grafana

vault_kv_secret_v2.grafana_oidc
  └── depends on: authentik_provider_oauth2.grafana
```

## Key Differences from Phase 1

1. **Two-tier group hierarchy:** Need to determine and respect parent/child relationship
2. **Monitoring tier application:** Different domain from critical infrastructure
3. **Potential existing Vault secrets:** May need to merge like Mealie pattern

## Implementation Strategy

### Workflow

1. **Setup:**
   - Create worktree: `.worktrees/grafana-oidc`
   - Branch: `feat/grafana-oidc-integration`
   - Working directory: `tf/authentik/`

2. **Discovery Phase:**
   - Identify group hierarchy (parent/child relationship)
   - Get resource UUIDs for groups, provider, application
   - Check provider configuration (flows, certificates, scopes)
   - Verify if Vault secrets exist at `secret/fzymgc-house/cluster/grafana`

3. **Task-by-Task Import:**
   - **Task 1:** Import Grafana groups (parent first, then child)
   - **Task 2:** Import Grafana OAuth2 provider
   - **Task 3:** Import Grafana application
   - **Task 4:** Store OIDC credentials in Vault
   - **Task 5:** Validation and documentation

4. **Code Review:** After each task completion

5. **PR Creation:** When all tasks complete and validate

### Task Details

#### Task 1: Import Grafana Groups

**Discovery:**
```bash
# Find groups
terraform import authentik_group.grafana_editor <uuid>
terraform import authentik_group.grafana_admin <uuid>
```

**File:** `grafana.tf`
```hcl
# Groups for Grafana access control
resource "authentik_group" "grafana_editor" {
  name = "grafana-editor"
}

resource "authentik_group" "grafana_admin" {
  name         = "grafana-admin"
  parent       = authentik_group.grafana_editor.id
  is_superuser = false
}
```

**Validation:**
- `terraform plan` shows no changes for groups
- Group hierarchy preserved

#### Task 2: Import Grafana OAuth2 Provider

**Discovery:**
```bash
# Find provider ID
terraform import authentik_provider_oauth2.grafana <id>
```

**File:** `grafana.tf`
```hcl
# OAuth2 Provider for Grafana
resource "authentik_provider_oauth2" "grafana" {
  name      = "Provider for Grafana"
  client_id = "<discovered-client-id>"

  authorization_flow    = data.authentik_flow.default_authorization_flow.id
  invalidation_flow     = data.authentik_flow.default_provider_invalidation_flow.id
  access_token_validity = "minutes=5"

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://grafana.fzymgc.house/login/generic_oauth"
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

**Note:** If data sources don't match actual state, use hardcoded UUIDs with documentation like Phase 1.

**Validation:**
- `terraform plan` shows no changes for provider
- All configuration matches Authentik state

#### Task 3: Import Grafana Application

**Discovery:**
```bash
# Find application by slug
terraform import authentik_application.grafana grafana
```

**File:** `grafana.tf`
```hcl
# Grafana Application
resource "authentik_application" "grafana" {
  name              = "Grafana"
  slug              = "grafana"
  protocol_provider = authentik_provider_oauth2.grafana.id
  meta_launch_url   = "https://grafana.fzymgc.house"
  meta_description  = "Metrics and monitoring dashboards"
}
```

**Validation:**
- `terraform plan` shows no changes for application
- Application correctly linked to provider

#### Task 4: Store OIDC Credentials in Vault

**Check existing secrets:**
```bash
vault kv get secret/fzymgc-house/cluster/grafana
```

**Pattern A:** No existing secrets
```hcl
# Store Grafana OIDC credentials in Vault for cluster consumption
resource "vault_kv_secret_v2" "grafana_oidc" {
  mount = "secret"
  name  = "fzymgc-house/cluster/grafana/oidc"

  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.grafana.client_id
    client_secret = authentik_provider_oauth2.grafana.client_secret
  })
}
```

**Pattern B:** Existing secrets (like Mealie)
```hcl
# Read existing Grafana secrets from Vault
data "vault_kv_secret_v2" "grafana_existing" {
  mount = "secret"
  name  = "fzymgc-house/cluster/grafana"
}

# Store OAuth2 credentials in Vault (merge with existing secrets)
resource "vault_kv_secret_v2" "grafana" {
  mount = "secret"
  name  = "fzymgc-house/cluster/grafana"

  data_json = jsonencode(merge(
    data.vault_kv_secret_v2.grafana_existing.data,
    {
      oidc_client_id     = authentik_provider_oauth2.grafana.client_id
      oidc_client_secret = authentik_provider_oauth2.grafana.client_secret
    }
  ))
}
```

**Validation:**
- Credentials stored in Vault
- `terraform plan` shows no changes
- Can retrieve credentials from Vault

#### Task 5: Validation and Documentation

**Validation Steps:**
1. Run `terraform plan -detailed-exitcode` (should exit 0)
2. Verify all resources in state: `terraform state list | grep grafana`
3. Manual Grafana OIDC login test at https://grafana.fzymgc.house
4. Create `VALIDATION.md` documenting results

**Documentation:**
```markdown
# Grafana OIDC Integration Validation Results

**Date:** 2025-11-28
**Branch:** feat/grafana-oidc-integration

## Resources Imported

- Groups (2): grafana-editor (parent), grafana-admin (child)
- OAuth2 Provider (1): Grafana OIDC provider
- Application (1): Grafana
- Vault Secret (1): secret/fzymgc-house/cluster/grafana/oidc

## Terraform State Verification

terraform plan -detailed-exitcode
Exit Code: 0
Result: No changes needed

## Manual Testing

- [ ] Grafana OIDC login successful
- [ ] Group permissions preserved
- [ ] Dashboards accessible

## Files Created

- tf/authentik/grafana.tf
```

## Risk Mitigation

### Known Risks (from Phase 1)

**Hardcoded UUIDs:**
- Use data sources where possible
- Document hardcoded UUIDs with comments and TODOs
- Verify no drift with `terraform plan`

**Service Disruption:**
- Import preserves existing resources
- No credential regeneration
- Test authentication after import

### New Risks

**Two-tier Group Hierarchy:**
- Risk: Import wrong order breaks dependency
- Mitigation: Discover hierarchy first, import parent before child

**Existing Vault Secrets:**
- Risk: Overwrite existing secrets
- Mitigation: Check before writing, merge if needed (Mealie pattern)

**Group Membership:**
- Risk: Lose user assignments
- Mitigation: Import doesn't modify membership, only brings groups under Terraform

## Success Criteria

**Technical:**
- All 2 groups imported successfully
- OAuth2 provider under Terraform management
- Application correctly linked to provider
- `terraform plan` shows no changes (exit code 0)
- OIDC credentials stored in Vault

**Operational:**
- Zero downtime during import
- Grafana OIDC login works identically
- User permissions unchanged
- Group memberships preserved

## Rollback Plan

If issues occur:
1. `terraform state rm` problematic resources
2. Re-import with corrected configuration
3. Terraform state is backed up before starting
4. Authentik resources unchanged (import is read-only)

## Next Steps

After successful merge:
1. Phase 2b: NAS LDAP Integration
2. Phase 3: User Applications (Paperless, Windmill, etc.)

## References

- Phase 1 PR: #66
- Design Document: docs/plans/2025-11-28-authentik-iac-migration-design.md
- Authentik Provider Docs: https://registry.terraform.io/providers/goauthentik/authentik/latest/docs
