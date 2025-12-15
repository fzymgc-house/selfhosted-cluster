# NAS LDAP Integration - Phase 2b Design

**Date:** 2025-11-28
**Phase:** 2b of Authentik IaC Migration
**Status:** Design Complete

## Overview

Import the NAS LDAP provider, application, and any associated groups into Terraform following the proven Phase 2a (Grafana) pattern. This brings NAS authentication under Infrastructure as Code management with zero service disruption.

**Key Difference from Phase 2a:** NAS uses an **LDAP provider** instead of OAuth2. LDAP providers have different configuration attributes but follow the same import workflow.

## Scope

**Resources to Import (discovered during implementation):**
- **Groups:** To be discovered - may include nas-admin, nas-users, or similar
- **LDAP Provider:** Existing NAS LDAP provider in Authentik
- **Application:** NAS application in Authentik
- **Vault Credentials:** Store LDAP bind credentials at `secret/fzymgc-house/cluster/nas/ldap` or `secret/fzymgc-house/cluster/nas`

**Out of Scope:**
- NAS configuration changes (Samba, NFS, etc.)
- User/group membership modifications
- LDAP schema or attribute changes
- Certificate management

**Success Criteria:**
- All NAS LDAP resources under Terraform management
- `terraform plan` shows exit code 0 (no drift)
- LDAP credentials stored in Vault with custom metadata
- NAS authentication continues working identically
- Zero service disruption

## Architecture

### File Structure

```
tf/authentik/
├── data-sources.tf        # Shared data sources (existing)
├── grafana.tf             # Grafana OIDC integration (existing)
├── nas.tf                 # NEW: NAS LDAP integration
├── vault.tf               # Existing
├── argocd.tf              # Existing
├── argo-workflows.tf      # Existing
└── mealie.tf              # Existing
```

### Resource Dependencies

```
authentik_group.nas_* (if any exist)
  └── Parent/child relationships TBD during discovery

authentik_provider_ldap.nas
  ├── No flow dependencies (LDAP doesn't use auth flows)
  ├── May depend on certificate for TLS
  └── Configured with base DN, bind settings

authentik_application.nas
  └── depends on: authentik_provider_ldap.nas

vault_kv_secret_v2.nas_ldap (or nas)
  └── depends on: authentik_provider_ldap.nas
```

### Key LDAP Provider Attributes (to be discovered)

- `base_dn` - LDAP base distinguished name (e.g., `dc=fzymgc,dc=house`)
- `bind_mode` - How NAS authenticates (likely `cached` or `direct`)
- `search_group` - Optional group filter for LDAP searches
- `certificate` - TLS certificate for secure LDAP
- `uid_start_number` / `gid_start_number` - Unix UID/GID ranges

### Pattern Consistency

Like Grafana, NAS will follow the established pattern:
1. Groups (if any) → Provider → Application → Vault storage
2. Hardcoded UUIDs with TODO comments where data sources don't match
3. Custom metadata on Vault secrets
4. Zero-drift verification after each import

## Key Differences from Phase 2a (Grafana)

### Provider Type - LDAP vs OAuth2

- **OAuth2 (Grafana):** Uses flows, redirect URIs, property mappings, token validity
- **LDAP (NAS):** Uses base DN, bind mode, UID/GID ranges, search filters
- **Impact:** Different Terraform attributes, but same import workflow

### Authentication Model

- **OAuth2:** Browser-based SSO with authorization codes
- **LDAP:** Direct bind authentication for services (Samba, NFS)
- **Impact:** Different credential types in Vault (client_id/secret vs bind DN/password)

### No Authorization Flows

- LDAP providers don't use Authentik flows
- Simpler dependency chain than OAuth2

### Potential Group Differences

- Grafana had explicit 2-tier hierarchy (editor → admin)
- NAS groups may not exist or have different structure
- Will discover during Task 1

## Implementation Strategy

### Workflow

1. **Setup:**
   - Create worktree: `.worktrees/nas-ldap`
   - Branch: `feat/nas-ldap-integration`
   - Working directory: `tf/authentik/`

2. **Discovery Phase:**
   - Identify NAS-related groups in Authentik (if any)
   - Get LDAP provider ID and configuration
   - Get application slug and metadata
   - Check for existing Vault secrets at `secret/fzymgc-house/cluster/nas`
   - Document findings in `NAS_IDS.txt`

3. **Task-by-Task Import:**
   - **Task 1:** Discovery - gather all resource IDs and configuration
   - **Task 2:** Import NAS groups (if any exist)
   - **Task 3:** Import NAS LDAP provider
   - **Task 4:** Import NAS application
   - **Task 5:** Store LDAP credentials in Vault
   - **Task 6:** Validation and documentation
   - **Task 7:** Create pull request

4. **Code Review:** After each task completion (Tasks 2-5)

5. **PR Creation:** When all tasks complete and validate

### Task Details

#### Task 1: Discovery

**Objective:** Gather all NAS LDAP resource IDs and configuration details.

**Commands:**
```bash
# Find LDAP providers
curl -H "Authorization: Bearer $TOKEN" \
  https://auth.fzymgc.house/api/v3/providers/ldap/ | jq

# Find NAS application
curl -H "Authorization: Bearer $TOKEN" \
  https://auth.fzymgc.house/api/v3/core/applications/ | jq '.results[] | select(.slug | contains("nas"))'

# Search for NAS-related groups
curl -H "Authorization: Bearer $TOKEN" \
  https://auth.fzymgc.house/api/v3/core/groups/ | jq '.results[] | select(.name | contains("nas"))'

# Check Vault for existing secrets
vault kv get secret/fzymgc-house/cluster/nas
```

**Documentation:** Create `NAS_IDS.txt` with:
- LDAP provider ID and configuration
- Application slug and metadata
- Group UUIDs (if found)
- Existing Vault secret paths (if any)
- All LDAP-specific settings (base_dn, bind_mode, etc.)

#### Task 2: Import Groups (if found)

**Condition:** Only if NAS groups exist in Authentik.

**File:** `nas.tf`
```hcl
# Groups for NAS access control (if applicable)
resource "authentik_group" "nas_users" {
  name = "nas-users"
}

resource "authentik_group" "nas_admin" {
  name         = "nas-admin"
  parent       = authentik_group.nas_users.id  # If hierarchy exists
  is_superuser = false
}
```

**Import Commands:**
```bash
terraform import authentik_group.nas_users <uuid>
terraform import authentik_group.nas_admin <uuid>
```

**Validation:**
- `terraform plan` shows no changes for groups
- Group hierarchy preserved (if applicable)

#### Task 3: Import LDAP Provider

**File:** `nas.tf`
```hcl
# LDAP Provider for NAS
resource "authentik_provider_ldap" "nas" {
  name    = "Provider for NAS"
  base_dn = "<discovered-base-dn>"  # e.g., "dc=fzymgc,dc=house"

  # Bind mode: how NAS authenticates
  bind_mode = "<discovered-mode>"  # likely "cached" or "direct"

  # UID/GID ranges for Unix attributes
  uid_start_number = <discovered-uid-start>
  gid_start_number = <discovered-gid-start>

  # Optional: search group filter
  search_group = <group-uuid-if-used>

  # Optional: TLS certificate
  # If certificate UUID doesn't match data source, use hardcoded with TODO
  certificate = "<certificate-uuid>"
}
```

**Import Command:**
```bash
terraform import authentik_provider_ldap.nas <id>
```

**Note:** If certificate or other UUIDs don't match data sources, use hardcoded values with documentation like Phase 2a.

**Validation:**
- `terraform plan` shows no changes for provider
- All LDAP configuration matches Authentik state

#### Task 4: Import Application

**File:** `nas.tf`
```hcl
# NAS Application
resource "authentik_application" "nas" {
  name              = "NAS"
  slug              = "<discovered-slug>"  # likely "nas" or similar
  protocol_provider = authentik_provider_ldap.nas.id
  meta_launch_url   = "<discovered-url>"  # NAS web interface URL
  meta_description  = "Network Attached Storage (Samba/NFS)"
}
```

**Import Command:**
```bash
terraform import authentik_application.nas <slug>
```

**Validation:**
- `terraform plan` shows no changes for application
- Application correctly linked to LDAP provider

#### Task 5: Store LDAP Credentials in Vault

**Check existing secrets:**
```bash
vault kv get secret/fzymgc-house/cluster/nas
```

**Pattern A:** No existing secrets
```hcl
# Store NAS LDAP credentials in Vault for cluster consumption
resource "vault_kv_secret_v2" "nas_ldap" {
  mount = "secret"
  name  = "fzymgc-house/cluster/nas/ldap"

  data_json = jsonencode({
    bind_dn       = authentik_provider_ldap.nas.bind_dn
    bind_password = authentik_provider_ldap.nas.bind_password
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by  = "terraform"
      application = "nas"
    }
  }
}
```

**Pattern B:** Existing secrets (merge pattern)
```hcl
# Read existing NAS secrets from Vault
data "vault_kv_secret_v2" "nas_existing" {
  mount = "secret"
  name  = "fzymgc-house/cluster/nas"
}

# Store LDAP credentials in Vault (merge with existing secrets)
resource "vault_kv_secret_v2" "nas" {
  mount = "secret"
  name  = "fzymgc-house/cluster/nas"

  data_json = jsonencode(merge(
    data.vault_kv_secret_v2.nas_existing.data,
    {
      ldap_bind_dn       = authentik_provider_ldap.nas.bind_dn
      ldap_bind_password = authentik_provider_ldap.nas.bind_password
    }
  ))

  custom_metadata {
    max_versions = 5
    data = {
      managed_by  = "terraform"
      application = "nas"
    }
  }
}
```

**Validation:**
- Credentials stored in Vault
- `terraform plan` shows no changes
- Can retrieve credentials from Vault

#### Task 6: Validation and Documentation

**Validation Steps:**
1. Run `terraform plan -detailed-exitcode` (should exit 0)
2. Verify all resources in state: `terraform state list | grep nas`
3. Manual NAS LDAP authentication test (Samba/NFS)
4. Create `VALIDATION_NAS.md` documenting results

**Documentation Template:**
```markdown
# NAS LDAP Integration Validation Results

**Date:** 2025-11-28
**Branch:** feat/nas-ldap-integration

## Resources Imported

- Groups (if any): [list]
- LDAP Provider (1): NAS LDAP provider
- Application (1): NAS
- Vault Secret (1): secret/fzymgc-house/cluster/nas/ldap (or nas)

## Terraform State Verification

terraform plan -detailed-exitcode
Exit Code: [0/1/2]
Result: [No changes needed / Changes detected]

## Manual Testing

- [ ] Samba file shares accessible
- [ ] NFS mounts working
- [ ] LDAP user authentication successful
- [ ] Permissions preserved

## Files Created

- tf/authentik/nas.tf
```

#### Task 7: Create Pull Request

**PR Title:**
```
feat(authentik): Import NAS LDAP integration into Terraform (Phase 2b)
```

**PR Description:** Include:
- Summary of resources imported
- LDAP-specific configuration details
- Validation results
- Manual testing checklist
- Reference to design document

## Risk Mitigation

### Known Risks (from Phase 2a)

**Hardcoded Attribute Values:**
- Risk: base_dn, certificate UUIDs may not match data sources
- Mitigation: Use hardcoded values with TODO comments, document in discovery notes

**Service Disruption:**
- Risk: Import changes LDAP configuration
- Mitigation: Import preserves existing resources, verify with terraform plan before apply

**Existing Vault Secrets:**
- Risk: Overwrite NAS secrets if they exist
- Mitigation: Check before writing, use merge pattern (Pattern B) if needed

### LDAP-Specific Risks

**Complex LDAP Configuration:**
- Risk: LDAP has many attributes (base DN, search filters, UID ranges)
- Mitigation: Comprehensive discovery phase, document all settings in NAS_IDS.txt

**Certificate Dependencies:**
- Risk: LDAP may require TLS certificate reference
- Mitigation: Discover certificate during Task 1, handle like signing_key in Grafana

**Bind Credentials:**
- Risk: LDAP bind password different from OAuth2 client_secret
- Mitigation: Store in Vault with clear key names (bind_dn, bind_password)

**Group Membership:**
- Risk: Lose user assignments during import
- Mitigation: Import doesn't modify membership, only brings groups under Terraform

## Success Criteria

### Technical

- All NAS LDAP resources imported into Terraform state
- LDAP provider configuration matches Authentik state exactly
- Application correctly linked to LDAP provider
- `terraform plan -detailed-exitcode` returns exit code 0 (no drift)
- LDAP credentials stored in Vault with custom metadata
- Groups imported (if they exist)

### Operational

- Zero downtime during import process
- NAS LDAP authentication works identically before and after
- File share access unchanged
- User permissions preserved
- No NAS configuration changes required

### Quality

- Code reviewed after each task
- All validation steps documented in VALIDATION_NAS.md
- Follows Phase 2a patterns exactly
- Comprehensive discovery notes in NAS_IDS.txt

## Rollback Plan

If issues occur:
1. `terraform state rm` problematic resources
2. Re-import with corrected configuration
3. Terraform state is backed up before starting (automatic in Terraform Cloud)
4. Authentik resources unchanged (import is read-only)
5. Vault secrets can be reverted if needed

## Next Steps

After successful merge:
1. Verify NAS file shares accessible
2. Test LDAP authentication manually
3. Phase 3: User Applications (Paperless, Windmill, Karakeep, Komodo, fzymgc)

## References

- Phase 1 PR: #66 (Critical Infrastructure)
- Phase 2a PR: #67 (Grafana OIDC)
- Master Design: `docs/plans/2025-11-28-authentik-iac-migration-design.md`
- Grafana Design: `docs/plans/2025-11-28-grafana-oidc-design.md`
- Authentik LDAP Provider Docs: https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/provider_ldap
