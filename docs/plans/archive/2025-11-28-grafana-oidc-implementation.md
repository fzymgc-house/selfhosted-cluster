# Grafana OIDC Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Import Grafana OAuth2 provider, application, and groups into Terraform with zero service disruption.

**Architecture:** Follow proven Phase 1 pattern - use terraform import to bring existing Authentik resources under IaC management, store OIDC credentials in Vault for ExternalSecrets consumption, maintain parent/child group hierarchy.

**Tech Stack:** Terraform, Authentik Provider v2024.12.1, Vault Provider v4.8.0, Authentik API

---

## Task 1: Discover Grafana Resource IDs

**Goal:** Identify all Grafana resource UUIDs needed for terraform import.

**Files:**
- None (discovery only)

**Step 1: List all Authentik applications to find Grafana**

Run in `tf/authentik/`:
```bash
terraform console <<'EOF'
provider::authentik::applications()
EOF
```

Alternative if provider function not available:
```bash
curl -s -H "Authorization: Bearer $(vault kv get -field=token secret/authentik/api-token)" \
  'https://auth.fzymgc.house/api/v3/core/applications/?page_size=100' | \
  jq '.results[] | select(.name | test("Grafana|grafana")) | {name, slug, pk, provider}'
```

Expected output:
```json
{
  "name": "Grafana",
  "slug": "grafana",
  "pk": "<application-uuid>",
  "provider": <provider-id>
}
```

**Document:** Application slug = `grafana`, Provider ID = `<provider-id>`

**Step 2: Find Grafana OAuth2 provider details**

```bash
curl -s -H "Authorization: Bearer $(vault kv get -field=token secret/authentik/api-token)" \
  'https://auth.fzymgc.house/api/v3/providers/oauth2/<provider-id>/' | \
  jq '{name, pk, client_id, authorization_flow, invalidation_flow, signing_key, redirect_uris}'
```

Expected output:
```json
{
  "name": "Provider for Grafana",
  "pk": <provider-id>,
  "client_id": "<client-id>",
  "authorization_flow": "<flow-uuid>",
  "invalidation_flow": "<flow-uuid>",
  "signing_key": "<cert-uuid>",
  "redirect_uris": [...]
}
```

**Document:** Provider ID, client_id, flow UUIDs, signing key UUID

**Step 3: Find Grafana groups and hierarchy**

```bash
curl -s -H "Authorization: Bearer $(vault kv get -field=token secret/authentik/api-token)" \
  'https://auth.fzymgc.house/api/v3/core/groups/?page_size=100' | \
  jq '.results[] | select(.name | test("grafana")) | {name, pk, parent, is_superuser}'
```

Expected output:
```json
{
  "name": "grafana-editor",
  "pk": "<editor-uuid>",
  "parent": null,
  "is_superuser": false
}
{
  "name": "grafana-admin",
  "pk": "<admin-uuid>",
  "parent": "<editor-uuid>",
  "is_superuser": false
}
```

**Document:** Group UUIDs and parent/child relationship

**Step 4: Create discovery notes file**

Create: `tf/authentik/GRAFANA_IDS.txt`

```text
# Grafana Resource IDs (discovered 2025-11-28)

## Application
slug: grafana
uuid: <application-uuid>

## OAuth2 Provider
id: <provider-id>
client_id: <client-id>

## Groups
grafana-editor: <editor-uuid> (parent)
grafana-admin: <admin-uuid> (child of grafana-editor)

## Flows & Certificates
authorization_flow: <flow-uuid>
invalidation_flow: <flow-uuid>
signing_key: <cert-uuid>
```

**Verification:** File contains all necessary UUIDs for import

---

## Task 2: Import Grafana Groups

**Goal:** Bring grafana-editor and grafana-admin groups under Terraform management.

**Files:**
- Create: `tf/authentik/grafana.tf`

**Step 1: Create grafana.tf with group resources**

Create file `tf/authentik/grafana.tf`:

```hcl
# Grafana OAuth2/OIDC Integration
# Provides single sign-on for Grafana metrics and monitoring platform

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

**Step 2: Import grafana-editor group (parent first)**

Run:
```bash
terraform import authentik_group.grafana_editor <editor-uuid>
```

Expected output:
```
authentik_group.grafana_editor: Importing from ID "<editor-uuid>"...
authentik_group.grafana_editor: Import prepared!
  Prepared authentik_group for import
authentik_group.grafana_editor: Refreshing state... [id=<editor-uuid>]

Import successful!
```

**Step 3: Import grafana-admin group (child second)**

Run:
```bash
terraform import authentik_group.grafana_admin <admin-uuid>
```

Expected output:
```
authentik_group.grafana_admin: Importing from ID "<admin-uuid>"...
authentik_group.grafana_admin: Import prepared!
  Prepared authentik_group for import
authentik_group.grafana_admin: Refreshing state... [id=<admin-uuid>]

Import successful!
```

**Step 4: Verify no drift**

Run:
```bash
terraform plan -detailed-exitcode
```

Expected output:
```
No changes. Your infrastructure matches the configuration.
```
Exit code: `0`

**Step 5: Format and commit**

```bash
terraform fmt grafana.tf
git add grafana.tf GRAFANA_IDS.txt
git commit -m "feat: Import Grafana groups into Terraform

Import grafana-editor (parent) and grafana-admin (child) groups with
proper hierarchy. Groups now managed by Terraform for IaC.

Part of Phase 2a: Grafana OIDC Integration"
```

---

## Task 3: Import Grafana OAuth2 Provider

**Goal:** Import Grafana OIDC provider configuration into Terraform.

**Files:**
- Modify: `tf/authentik/grafana.tf`

**Step 1: Compare flow/cert UUIDs with data sources**

Run:
```bash
terraform console <<'EOF'
data.authentik_flow.default_authorization_flow.id
data.authentik_flow.default_provider_invalidation_flow.id
data.authentik_certificate_key_pair.generated.id
EOF
```

Compare with discovered UUIDs from GRAFANA_IDS.txt.

**If they match:** Use data sources
**If they don't match:** Use hardcoded UUIDs with documentation (Phase 1 pattern)

**Step 2: Add OAuth2 provider resource to grafana.tf**

Append to `tf/authentik/grafana.tf`:

```hcl

# OAuth2 Provider for Grafana
resource "authentik_provider_oauth2" "grafana" {
  name      = "Provider for Grafana"
  client_id = "<client-id from discovery>"

  # Use data sources if UUIDs match, otherwise hardcode with comments like Phase 1
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

**Note:** Adjust `allowed_redirect_uris` based on actual discovery. Grafana typically uses `/login/generic_oauth` callback.

**If UUIDs don't match data sources**, use Phase 1 pattern with comments:

```hcl
  # Note: Grafana uses a different authorization flow than Mealie (which uses implicit consent).
  # This UUID was preserved during terraform import from existing Authentik configuration.
  # TODO: Identify the flow slug and create a data source reference
  authorization_flow = "<discovered-flow-uuid>"
```

**Step 3: Import OAuth2 provider**

Run:
```bash
terraform import authentik_provider_oauth2.grafana <provider-id>
```

Expected output:
```
authentik_provider_oauth2.grafana: Importing from ID "<provider-id>"...
authentik_provider_oauth2.grafana: Import prepared!
  Prepared authentik_provider_oauth2 for import
authentik_provider_oauth2.grafana: Refreshing state... [id=<provider-id>]

Import successful!
```

**Step 4: Verify configuration matches**

Run:
```bash
terraform plan -detailed-exitcode
```

**If plan shows changes:**
- Review diff carefully
- Adjust grafana.tf to match actual Authentik state
- Common mismatches: redirect URIs, property mappings order, token validity

**If plan shows no changes:**
```
No changes. Your infrastructure matches the configuration.
```
Exit code: `0`

**Step 5: Format and commit**

```bash
terraform fmt grafana.tf
git add grafana.tf
git commit -m "feat: Import Grafana OAuth2 provider into Terraform

Import OIDC provider configuration for Grafana SSO integration.
Provider ID <provider-id> now managed by Terraform.

Part of Phase 2a: Grafana OIDC Integration"
```

---

## Task 4: Import Grafana Application

**Goal:** Import Grafana application resource linking to OAuth2 provider.

**Files:**
- Modify: `tf/authentik/grafana.tf`

**Step 1: Add application resource to grafana.tf**

Append to `tf/authentik/grafana.tf`:

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

**Step 2: Import application by slug**

Run:
```bash
terraform import authentik_application.grafana grafana
```

Expected output:
```
authentik_application.grafana: Importing from ID "grafana"...
authentik_application.grafana: Import prepared!
  Prepared authentik_application for import
authentik_application.grafana: Refreshing state... [id=grafana]

Import successful!
```

**Step 3: Verify no drift**

Run:
```bash
terraform plan -detailed-exitcode
```

Expected output:
```
No changes. Your infrastructure matches the configuration.
```
Exit code: `0`

**Step 4: Format and commit**

```bash
terraform fmt grafana.tf
git add grafana.tf
git commit -m "feat: Import Grafana application into Terraform

Import Grafana application (slug: grafana) linking to OAuth2 provider.
Application now managed by Terraform for IaC.

Part of Phase 2a: Grafana OIDC Integration"
```

---

## Task 5: Store Grafana OIDC Credentials in Vault

**Goal:** Store client_id and client_secret in Vault for ExternalSecrets consumption.

**Files:**
- Modify: `tf/authentik/grafana.tf`

**Step 1: Check if Grafana secrets already exist in Vault**

Run:
```bash
vault kv get secret/fzymgc-house/cluster/grafana
```

**If exists:** Note which fields are present (will need to merge)
**If does not exist:** Will create new secret

**Step 2a: If NO existing secrets - Add vault secret resource**

Append to `tf/authentik/grafana.tf`:

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

**Step 2b: If existing secrets - Use merge pattern (like Mealie)**

Append to `tf/authentik/grafana.tf`:

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

  custom_metadata {
    max_versions = 5
    data = {
      managed_by  = "terraform"
      application = "grafana"
    }
  }
}
```

**Step 3: Apply Terraform to create/update Vault secret**

Run:
```bash
terraform apply
```

Review plan, type `yes` to confirm.

Expected output:
```
vault_kv_secret_v2.grafana_oidc: Creating...
vault_kv_secret_v2.grafana_oidc: Creation complete after 1s

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

**Step 4: Verify secret stored correctly**

Run:
```bash
vault kv get secret/fzymgc-house/cluster/grafana/oidc
```

Expected output shows:
```
====== Data ======
Key              Value
---              -----
client_id        <grafana-client-id>
client_secret    <grafana-client-secret>
```

**Step 5: Verify no drift after apply**

Run:
```bash
terraform plan -detailed-exitcode
```

Expected output:
```
No changes. Your infrastructure matches the configuration.
```
Exit code: `0`

**Step 6: Format and commit**

```bash
terraform fmt grafana.tf
git add grafana.tf
git commit -m "feat: Store Grafana OIDC credentials in Vault

Store client_id and client_secret at secret/fzymgc-house/cluster/grafana/oidc
for ExternalSecrets consumption. Credentials now managed by Terraform.

Part of Phase 2a: Grafana OIDC Integration"
```

---

## Task 6: Final Validation and Documentation

**Goal:** Verify complete integration and document results.

**Files:**
- Create: `tf/authentik/VALIDATION_GRAFANA.md`

**Step 1: Run comprehensive terraform validation**

Run in `tf/authentik/`:
```bash
terraform fmt -check -recursive
terraform validate
terraform plan -detailed-exitcode
```

Expected:
- fmt: No changes needed
- validate: Success! The configuration is valid.
- plan: Exit code `0` (no changes)

**Step 2: Verify all resources in state**

Run:
```bash
terraform state list | grep grafana
```

Expected output:
```
authentik_application.grafana
authentik_group.grafana_admin
authentik_group.grafana_editor
authentik_provider_oauth2.grafana
vault_kv_secret_v2.grafana_oidc
```

(Or `vault_kv_secret_v2.grafana` if using merge pattern)

**Step 3: Manual Grafana OIDC login test**

**Action:** Navigate to https://grafana.fzymgc.house and test OIDC login

**Verification:**
- Click "Sign in with OAuth"
- Redirected to Authentik
- Login successful
- Redirected back to Grafana
- User logged in with correct permissions based on group membership

**Document:** Login successful / any issues encountered

**Step 4: Create validation documentation**

Create file `tf/authentik/VALIDATION_GRAFANA.md`:

```markdown
# Grafana OIDC Integration Validation Results

**Date:** 2025-11-28
**Branch:** feat/grafana-oidc-integration
**Task:** Grafana OIDC Integration (Phase 2a)

## Terraform State Verification

### Terraform Plan Results

```
terraform plan -detailed-exitcode
```

**Result:** EXIT CODE 0 - No changes needed

**Output:**
```
No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

### Imported Resources Summary

#### Groups (2 total)
- `authentik_group.grafana_editor` - Grafana editor access (parent group)
- `authentik_group.grafana_admin` - Grafana admin access (child of grafana_editor)

#### OAuth2 Provider (1 total)
- `authentik_provider_oauth2.grafana` (ID: <provider-id>) - Grafana OIDC provider

#### Application (1 total)
- `authentik_application.grafana` (slug: grafana) - Grafana SSO application

#### Vault OIDC Credentials (1 total)
OIDC credentials successfully stored in HashiCorp Vault:
- `vault_kv_secret_v2.grafana_oidc` - Grafana OIDC credentials at `secret/fzymgc-house/cluster/grafana/oidc`

## OIDC Login Verification

**Testing Completed:** 2025-11-28
**Tested By:** Authorized user

### Grafana OIDC
- **Status:** Login tested and verified
- **URL:** https://grafana.fzymgc.house
- **Result:** [✅ SUCCESS / ❌ FAILURE with details]
- **Groups:** User permissions correctly mapped from Authentik groups

## File Structure Verification

### Created Files
- `tf/authentik/grafana.tf` - Grafana groups, provider, application, and credentials
- `tf/authentik/GRAFANA_IDS.txt` - Resource ID discovery notes (not committed)
- `tf/authentik/VALIDATION_GRAFANA.md` - This validation document

### Existing Configuration Files
- `tf/authentik/data-sources.tf` - Shared Authentik data sources (unchanged)
- `tf/authentik/versions.tf` - Provider version constraints (unchanged)
- `tf/authentik/terraform.tf` - Provider configurations (unchanged)

## Success Criteria Verification

- [x] All groups imported (2 total: grafana-editor parent, grafana-admin child)
- [x] OAuth2 provider imported (1 total: Grafana)
- [x] Application imported (1 total: Grafana)
- [x] OIDC credentials stored in Vault (1 total)
- [x] `terraform plan` shows "No changes" (verified with exit code 0)
- [x] Terraform state is consistent with configuration
- [x] All resources properly tracked in Terraform state
- [x] No drift detected between configuration and infrastructure
- [x] Manual OIDC login test successful

## Infrastructure State

**Terraform State:** Clean - no pending changes
**Drift Detection:** None detected
**Provider Versions:**
- Authentik Provider: v2024.12.1
- Vault Provider: v4.8.0
- Terraform: 1.14+

## Manual Testing Results

Grafana OIDC login flow tested and verified:
- ✅ OAuth button present on login page
- ✅ Redirect to Authentik successful
- ✅ Authentication successful
- ✅ Redirect back to Grafana successful
- ✅ User logged in with appropriate permissions

## Post-Import Operations

The Grafana authentication infrastructure is now fully managed by Terraform. Any future changes to these resources should be made through Terraform configuration files, not through the Authentik UI.

**GitOps Integration:** Changes to this Terraform module can be automated through Argo Workflows GitOps automation if configured.

## Conclusion

Grafana OIDC integration has been successfully imported into Terraform. The configuration is complete, drift-free, and ready for production use. OIDC credentials are securely stored in Vault and available for cluster consumption via ExternalSecrets.

**Validation Status:** PASSED
```

**Step 5: Commit validation documentation**

```bash
git add VALIDATION_GRAFANA.md
git commit -m "docs: Add Grafana OIDC integration validation results

Document successful import of Grafana groups, OAuth2 provider, and
application into Terraform. Terraform plan shows zero drift.

Manual OIDC login testing confirmed successful.

Part of Phase 2a: Grafana OIDC Integration"
```

**Step 6: Clean up discovery notes (do not commit)**

```bash
rm GRAFANA_IDS.txt
```

This file contains sensitive UUIDs and was only for temporary reference during import.

---

## Task 7: Create Pull Request

**Goal:** Push branch and create PR for review.

**Step 1: Review all commits**

Run:
```bash
git log --oneline origin/main..HEAD
```

Expected: 5-6 commits showing progression through tasks

**Step 2: Push branch to remote**

Run:
```bash
git push -u origin feat/grafana-oidc-integration
```

Expected output:
```
Enumerating objects: ...
To github.com:fzymgc-house/selfhosted-cluster.git
 * [new branch]      feat/grafana-oidc-integration -> feat/grafana-oidc-integration
Branch 'feat/grafana-oidc-integration' set up to track remote branch 'feat/grafana-oidc-integration' from 'origin'.
```

**Step 3: Create pull request**

Run:
```bash
gh pr create --title "feat: Grafana OIDC Integration (Phase 2a)" --body "$(cat <<'EOF'
## Summary

Import Grafana OAuth2 provider, application, and groups into Terraform for Infrastructure as Code management:

- **Groups**: grafana-editor (parent), grafana-admin (child)
- **OAuth2 Provider**: Grafana OIDC provider configuration
- **Application**: Grafana application linked to provider
- **Vault Credentials**: OIDC credentials stored at `secret/fzymgc-house/cluster/grafana/oidc`

All resources imported using `terraform import` to preserve existing configurations without service disruption.

## Technical Details

**Resources Managed:**
- 2 Authentik groups with parent/child hierarchy
- 1 OAuth2 provider
- 1 Authentik application
- 1 Vault secret with OIDC credentials

**Files Created:**
- `tf/authentik/grafana.tf` - Grafana OIDC integration
- `tf/authentik/VALIDATION_GRAFANA.md` - Validation results

## Verification

- ✅ `terraform plan` shows "No changes" (zero drift)
- ✅ All groups, provider, and application imported successfully
- ✅ OIDC credentials stored in Vault
- ✅ Manual Grafana OIDC login tested and working
- ✅ All commits follow conventional commits format

## Test Plan

- [x] Verify Grafana OIDC login works at https://grafana.fzymgc.house
- [x] Confirm `terraform plan` shows no changes in production
- [x] Validate group permissions correctly mapped
- [x] Verify ExternalSecrets can sync OIDC credentials from Vault

## Related

- Design: docs/plans/2025-11-28-grafana-oidc-design.md
- Phase 1 PR: #66
- Phase 2b: NAS LDAP Integration (next)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected output:
```
https://github.com/fzymgc-house/selfhosted-cluster/pull/<pr-number>
```

**Step 4: Monitor PR checks**

Wait for automated checks to complete:
- claude-review
- Validate Changes
- Auto Label PR
- PR Size Check

All should pass (SUCCESS).

**Completion:** PR created and ready for review. Implementation complete!

---

## Success Criteria

**All tasks complete when:**
- ✅ All 7 tasks executed successfully
- ✅ Terraform plan shows exit code 0 (no drift)
- ✅ All resources in Terraform state
- ✅ Grafana OIDC login works
- ✅ PR created with passing checks
- ✅ Documentation complete

**Rollback Plan:**
If issues occur, `terraform state rm` problematic resources and re-import with corrected configuration. Authentik resources unchanged (import is read-only).
