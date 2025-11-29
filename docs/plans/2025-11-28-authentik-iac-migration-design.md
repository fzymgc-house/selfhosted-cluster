# Authentik Infrastructure as Code Migration Design

**Date:** 2025-11-28
**Status:** Complete (All Existing Resources Migrated)
**Completion Date:** 2025-11-29
**Author:** Claude Code

## Overview

Extract all Authentik applications, providers, and groups into Terraform configuration, using import to preserve existing resources without service disruption.

## Migration Results Summary

**Status:** ✅ Complete (All Existing Resources Migrated)

**Phases Completed:**
- ✅ **Phase 1:** Critical Infrastructure (Vault, ArgoCD, Argo Workflows, Mealie) - Pre-existing
- ✅ **Phase 2a:** Grafana OIDC Integration - PR #67 (Merged 2025-11-28)
- ✅ **Phase 2b:** NAS LDAP Integration - PR #68 (Merged 2025-11-29)
- ⏸️ **Phase 3:** User Applications - Deferred (applications not yet configured in Authentik)

**Resources Migrated:**
- 2 new applications (Grafana, NAS)
- 3 new groups (grafana-admins, grafana-editors, grafana-viewers)
- 2 new providers (OAuth2, LDAP)
- 1 new Vault secret

**Validation:** All migrated resources validated with zero configuration drift via `terraform plan -detailed-exitcode`.

**Documentation:** See `docs/plans/2025-11-28-authentik-iac-migration-completion.md` for detailed completion report.

## Goals

- Manage all Authentik access control resources as Infrastructure as Code
- Preserve existing resource IDs, credentials, and configurations
- Avoid service interruption during migration
- Enable version control and code review for identity/access changes

## Scope

**In Scope:**
- 11 applications across 3 provider types (OAuth2, Proxy, LDAP)
- 17 custom groups (excluding Authentik system groups)
- Vault integration for storing OAuth2/LDAP credentials
- Terraform import of existing resources

**Out of Scope:**
- Authentik flows (system defaults remain unmanaged)
- User accounts (managed in Authentik UI)
- Authentik system configuration (blueprints, policies, etc.)

## Architecture

### File Organization

Following the established `mealie.tf` pattern, each application gets its own file:

```
tf/authentik/
├── versions.tf              # Provider versions
├── terraform.tf             # Provider configurations
├── variables.tf             # Input variables
├── outputs.tf              # Output values
├── vault.tf                # Vault application
├── argocd.tf               # ArgoCD application
├── argo-workflows.tf       # Argo Workflows application
├── grafana.tf              # Grafana application
├── nas.tf                  # NAS application (LDAP)
├── fzymgc.tf               # fzymgc application (Proxy)
├── paperless.tf            # Paperless application
├── windmill.tf             # Windmill application
├── karakeep.tf             # Karakeep application
├── komodo.tf               # Komodo application
└── mealie.tf               # Mealie application (existing)
```

Each file contains all resources for that application:
- Access control groups
- Provider (OAuth2/Proxy/LDAP)
- Application definition
- Vault secret storage

### Resource Pattern

Each application file follows this structure:

```hcl
# 1. Groups - Define access control
resource "authentik_group" "app_users" {
  name = "app-users"
}

resource "authentik_group" "app_admin" {
  name         = "app-admin"
  parent       = authentik_group.app_users.id
  is_superuser = false
}

# 2. Data Sources - Reference shared resources
data "authentik_flow" "default_authorization_flow" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_certificate_key_pair" "generated" {
  name = "authentik Self-signed Certificate"
}

# 3. Provider - OAuth2/Proxy/LDAP configuration
resource "authentik_provider_oauth2" "app" {
  name               = "Provider for App"
  client_id          = "app"
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  # ... provider-specific settings
}

# 4. Application - Authentik application
resource "authentik_application" "app" {
  name              = "App"
  slug              = "app"
  protocol_provider = authentik_provider_oauth2.app.id
}

# 5. Vault Secret Storage - Store credentials
resource "vault_kv_secret_v2" "app_oidc" {
  mount = "secret"
  name  = "fzymgc-house/cluster/app/oidc"
  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.app.client_id
    client_secret = authentik_provider_oauth2.app.client_secret
  })
}
```

### Provider Types

**OAuth2 Providers** (9 applications)
- Applications: Vault, Grafana, ArgoCD, Argo Workflows, Paperless, Windmill, Karakeep, Komodo, Mealie
- Resource type: `authentik_provider_oauth2`
- Key attributes: client_id, client_secret, redirect_uris, scopes
- Most common pattern

**Proxy Provider** (1 application)
- Application: fzymgc
- Resource type: `authentik_provider_proxy`
- Key attributes: external_host, internal_host, mode
- Uses forward authentication (no client credentials)

**LDAP Provider** (1 application)
- Application: NAS
- Resource type: `authentik_provider_ldap`
- Key attributes: base_dn, bind_flow, search_group
- Traditional LDAP authentication

### Shared Resources

These resources are used by multiple applications and defined as data sources:

- `data.authentik_flow.default_authorization_flow` - OAuth2 authorization
- `data.authentik_flow.default_invalidation_flow` - Logout flow
- `data.authentik_certificate_key_pair.generated` - Default signing certificate
- `data.authentik_property_mapping_provider_scope.email` - Email scope mapping
- `data.authentik_property_mapping_provider_scope.openid` - OpenID scope mapping
- `data.authentik_property_mapping_provider_scope.profile` - Profile scope mapping

## Migration Strategy

### Import Approach

Use `terraform import` to bring existing resources under Terraform management:

**Advantages:**
- Preserves existing UUIDs, client IDs, and client secrets
- No service interruption - apps continue working unchanged
- Credentials in Vault remain valid
- No user impact

**Process:**
1. Fetch resource details from Authentik API
2. Write Terraform resource blocks
3. Import resources into Terraform state
4. Verify with `terraform plan` (should show "No changes")
5. Commit to version control

### Import Workflow

For each resource:

```bash
# 1. Get resource ID from Authentik API
curl -H "Authorization: Bearer $TOKEN" \
  https://auth.fzymgc.house/api/v3/core/groups/ | jq

# 2. Write Terraform resource block
# (in appropriate .tf file)

# 3. Import into state
terraform import authentik_group.vault_users <uuid>

# 4. Verify
terraform plan  # Should show "No changes"
```

## Implementation Phases

### Phase 1: Critical Infrastructure

**Applications:** Vault, ArgoCD, Argo Workflows

**Groups:**
- vault-users, vault-admin
- argocd-user, argocd-admin
- cluster-admin

**Files:** `vault.tf`, `argocd.tf`, `argo-workflows.tf`

**Validation:**
- `terraform plan` shows no changes
- Vault authentication works
- ArgoCD login works
- Argo Workflows login works

**Success Criteria:** All cluster management services authenticate correctly with no disruption.

### Phase 2: Monitoring & Storage

**Applications:** Grafana, NAS

**Groups:**
- grafana-admin, grafana-editor

**Files:** `grafana.tf`, `nas.tf`

**Special Considerations:**
- NAS uses LDAP provider (different resource type)
- Grafana has two-tier group hierarchy

**Validation:**
- Grafana dashboards accessible
- NAS LDAP authentication works

**Success Criteria:** Observability and storage services maintain authentication.

### Phase 3: User Applications ⏸️ DEFERRED

**Status:** Deferred - Applications not yet configured in Authentik

**Expected Applications:** Paperless, Windmill, Karakeep, Komodo, fzymgc

**Discovery Results (2025-11-29):**
- Authentik API query returned only 1 application: Mealie (already managed in Phase 1)
- None of the Phase 3 applications exist in Authentik
- Groups for these applications also not found

**Groups (When Created):**
- paperless-admin, paperless-users
- windmill-admin, windmill-users
- karakeep-users
- komodo-users

**Files (When Implemented):** `paperless.tf`, `windmill.tf`, `karakeep.tf`, `komodo.tf`, `fzymgc.tf`

**Special Considerations:**
- fzymgc uses Proxy provider (different resource type)
- Multiple apps with user/admin group hierarchies

**Recommendation:** Execute Phase 3 when these applications are deployed and configured in Authentik. Follow the patterns established in Phases 1-2 for OAuth2/Proxy imports.

**Success Criteria:** All user-facing applications work with no authentication issues.

## Risk Mitigation

### Import Challenges

**Challenge:** Finding resource UUIDs
**Solution:** Use Authentik API to fetch all resource IDs before import

**Challenge:** Client secrets are sensitive
**Solution:** Secrets already exist in Vault; Terraform will sync from Authentik's existing values

**Challenge:** Group hierarchies
**Solution:** Import parent groups before child groups to satisfy dependencies

**Challenge:** Provider assignments
**Solution:** Import provider before application that references it

**Challenge:** State conflicts
**Solution:** Use `terraform state rm` if import fails and needs retry

### Safety Measures

- Run `terraform plan` after each import (should show zero changes)
- Keep each phase in separate branch/PR for review
- Test critical infrastructure phase thoroughly before proceeding
- Document all resource IDs before starting import
- Have rollback plan (Terraform state backups)

## Data Management

### Vault Integration

OAuth2 and LDAP credentials are stored in Vault at:
- `secret/fzymgc-house/cluster/<app>/oidc` - OAuth2 apps
- `secret/fzymgc-house/cluster/<app>/ldap` - LDAP apps

Terraform manages these secrets to keep them in sync with Authentik provider configuration.

### Existing Credentials

During import, existing client secrets are preserved:
- Terraform reads current secret from Authentik
- Stores in Terraform state (encrypted in remote backend)
- Writes to Vault for cluster consumption
- No regeneration, no service disruption

## Success Criteria

**Technical:**
- All 11 applications imported successfully
- All 17 groups under Terraform management
- `terraform plan` shows no changes after import
- All authentication flows work identically

**Operational:**
- Zero downtime during migration
- All existing credentials remain valid
- Documentation updated
- Team can manage access via code review

## Future Enhancements

- Automated drift detection (compare Terraform state to Authentik API)
- Terraform module for new application onboarding
- Integration with CI/CD for automated testing
- Consider managing custom flows if needed

## References

- Authentik Terraform Provider: https://registry.terraform.io/providers/goauthentik/authentik
- Authentik API Documentation: https://auth.fzymgc.house/api/v3/schema/
- Existing mealie.tf implementation
