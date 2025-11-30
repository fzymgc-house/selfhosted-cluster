# Vault Migration Summary

## Overview

This document summarizes the migration from 1Password-based secrets to HashiCorp Vault for all infrastructure automation in the selfhosted-cluster repository.

## Changes Made

### 1. Ansible Configuration

**Files Modified:**
- `ansible/inventory/group_vars/tpi_alpha_hosts.yml` - BMC password now from Vault
- `ansible/inventory/group_vars/tpi_beta_hosts.yml` - BMC password now from Vault
- `ansible/inventory/group_vars/tp_cluster_nodes.yml` - Cloudflare API token and Vault root token now from Vault
- `ansible/ansible.cfg` - Removed `vault_password_file` reference

**Files Removed:**
- `ansible/.ansible_vault_password` - No longer needed (ansible-vault encrypted files will be migrated to Vault)

**Lookup Changes:**
```yaml
# Old (environment variable from .envrc)
tpi_bmc_password: "{{ lookup('ansible.builtin.env', 'TPI_ALPHA_BMC_ROOT_PW') }}"

# New (Vault lookup)
tpi_bmc_password: "{{ lookup('community.hashi_vault.vault_kv2_get', 'infrastructure/bmc/tpi-alpha', engine_mount_point='secret/fzymgc-house').secret.password }}"
```

```yaml
# Old (1Password lookup)
cloudflare_api_token: "{{ lookup('community.general.onepassword', 'cloudflare-api-token', vault='fzymgc-house', field='password') }}"

# New (Vault lookup)
cloudflare_api_token: "{{ lookup('community.hashi_vault.vault_kv2_get', 'infrastructure/cloudflare/api-token', engine_mount_point='secret/fzymgc-house').secret.token }}"
```

### 2. Terraform Configuration

**Files Modified:**
- `tf/authentik/versions.tf` - Removed onepassword provider
- `tf/authentik/terraform.tf` - Removed onepassword provider configuration
- `tf/vault/versions.tf` - Removed onepassword provider
- `tf/vault/terraform.tf` - Removed onepassword provider configuration
- `tf/core-services/versions.tf` - Removed onepassword provider
- `tf/core-services/terraform.tf` - Removed onepassword provider configuration

**Provider Changes:**
```hcl
# Removed from all modules
provider "onepassword" {
  account = "OGRXP4CXIVAVXIQ2QBBL7ZOHWE"
}
```

Terraform modules now rely solely on the Vault provider, which already existed for reading application secrets.

### 3. Development Environment

**Files Modified:**
- `.envrc` - Removed all hardcoded secrets, kept only configuration
- `.devcontainer/devcontainer.json` - Removed 1Password SSH agent mounting, added Vault token mounting
- `.devcontainer/post-create.sh` - Removed 1Password setup, added Vault authentication check

**Environment Changes:**
```bash
# Old .envrc
export TPI_BETA_BMC_ROOT_PW="My4Qmm3MdF9gR9LN*Ec@R"
export TPI_ALPHA_BMC_ROOT_PW="6tuMwPbehimYaoXRKsv6"

# New .envrc
export VAULT_ADDR=https://vault.fzymgc.house
# No secrets stored in file
```

**Devcontainer Changes:**
- Removed: 1Password SSH agent socket mounting
- Added: Vault token file mounting (`~/.vault-token`)
- Removed: `SSH_AUTH_SOCK` environment variable
- Kept: `VAULT_ADDR` environment variable

### 4. Scripts Created

**New Files:**
- `scripts/vault-helper.sh` - Helper for Vault operations (get/put/list/delete secrets)
- `scripts/migrate-secrets-to-vault.sh` - One-time migration script
- `scripts/README.md` - Documentation for scripts

### 5. Documentation

**New Files:**
- `docs/vault-migration.md` - Complete migration guide
- `docs/vault-migration-summary.md` - This file

**Modified Files:**
- `CLAUDE.md` - Updated with Vault authentication instructions and secret organization

## Vault Secret Structure

All infrastructure secrets are now stored in Vault:

```
secret/fzymgc-house/infrastructure/
├── bmc/
│   ├── tpi-alpha         # {password: "..."}
│   └── tpi-beta          # {password: "..."}
├── cloudflare/
│   └── api-token         # {token: "..."}
└── k3sup/
    └── ...               # Secrets from ansible-vault encrypted file (to be migrated)
```

**Note:** Vault root token is NOT stored in Vault (cannot store root token in Vault itself). Developers must authenticate with their own Vault token.

## Required Vault Policy

Developers need a Vault token with the `infrastructure-developer` policy attached. This policy grants read access to infrastructure secrets.

### Policy Definition

```hcl
# Policy: infrastructure-developer
path "secret/data/fzymgc-house/infrastructure/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/fzymgc-house/infrastructure/*" {
  capabilities = ["list"]
}

path "secret/data/fzymgc-house/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/fzymgc-house/*" {
  capabilities = ["list"]
}
```

### Creating the Policy (Vault Admin Only)

```bash
vault policy write infrastructure-developer infrastructure-developer-policy.hcl
```

See `docs/vault-migration.md` for complete policy setup instructions.

## Migration Steps (for users)

1. **Authenticate to Vault:**
   ```bash
   export VAULT_ADDR=https://vault.fzymgc.house
   vault login
   # Your token must have the infrastructure-developer policy attached
   ```

2. **Run Migration Script:**
   ```bash
   ./scripts/migrate-secrets-to-vault.sh
   ```

   This will:
   - Extract secrets from .envrc and 1Password
   - Create them in Vault
   - Verify successful creation

3. **Manually Migrate ansible-vault Encrypted Files:**
   ```bash
   # Decrypt and view the encrypted file
   cd ansible
   ansible-vault view roles/k3sup/vars/main.yml

   # Create secrets in Vault for each variable
   vault kv put secret/fzymgc-house/infrastructure/k3sup/<name> <key>=<value>
   ```

4. **Update Code (already done in this PR):**
   - Ansible group_vars now use `community.hashi_vault.vault_kv2_get` lookups
   - Terraform modules no longer use onepassword provider
   - .envrc no longer contains secrets
   - Devcontainer uses Vault for authentication

5. **Test:**
   ```bash
   # Test Ansible can retrieve secrets
   cd ansible
   ansible-playbook -i inventory/hosts.yml --check playbook.yml

   # Test Terraform can access Vault
   cd tf/authentik
   terraform init
   terraform plan
   ```

6. **Cleanup:**
   After verifying everything works:
   - Secrets remain in 1Password as backup (not deleted)
   - Old .envrc can be found in git history if needed
   - ansible-vault encrypted file can be deleted after migration

## Dependencies Removed

- 1Password CLI (`op` command) - No longer required
- 1Password account access - No longer required for infrastructure automation
- 1Password SSH agent - No longer mounted in devcontainer

## Dependencies Added

- HashiCorp Vault CLI (`vault` command) - Now required
- Valid Vault authentication token - Must run `vault login` before Ansible/Terraform operations

## Benefits

1. **Reduced Complexity:** One secrets management system instead of two
2. **Better DevContainer Support:** No external dependencies beyond Vault
3. **Centralized Secrets:** All infrastructure secrets in one place with audit logging
4. **No Secrets in Git:** .envrc no longer contains hardcoded passwords
5. **No Secrets in Environment:** Secrets retrieved on-demand, not exported to shell

## Backward Compatibility

**Breaking Changes:**
- 1Password CLI no longer used (must migrate to Vault)
- .envrc no longer contains secrets (must use Vault)
- ansible-vault password file removed (encrypted files must be migrated)

**Migration Path:**
Follow the steps in `docs/vault-migration.md` to complete the migration.

## Testing Checklist

- [ ] Vault authentication works: `vault login`
- [ ] Migration script completes successfully
- [ ] ansible-vault encrypted files decrypted and migrated
- [ ] Ansible playbooks run successfully with Vault secrets
- [ ] Terraform modules initialize and plan successfully
- [ ] Devcontainer builds and starts successfully
- [ ] No secrets remain in .envrc or environment variables
- [ ] Documentation updated with new workflow

## Rollback Plan

If issues arise:
1. Secrets still exist in 1Password (not deleted)
2. Old .envrc can be restored from git history: `git show HEAD~1:.envrc`
3. Ansible vault password script can be restored from git history
4. Revert Ansible group_vars changes to use old lookup methods
5. Re-add onepassword provider to Terraform modules

## Next Steps

After merging this PR:
1. All team members must run `vault login` before using Ansible/Terraform
2. Devcontainer users will see Vault authentication prompt on container start
3. CI/CD pipelines must be updated to use Vault authentication
4. Consider automating Vault token refresh for long-running development sessions
