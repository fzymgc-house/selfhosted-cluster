# Ansible-Vault Cleanup Task

## Issue

The file `ansible/roles/k3sup/vars/main.yml` is encrypted with ansible-vault and contains an unused variable `k3sup_onepassword_sdk_token` that is not referenced anywhere in the codebase.

## Verification

Searched the entire ansible directory and found:
- **Variable defined**: `ansible/roles/k3sup/vars/main.yml:18`
- **Variable used**: No references found

The variable appears to be a leftover from a previous configuration and is no longer needed.

## Current File Contents

The encrypted file contains two variables:
1. `k3sup_packages` - **USED** in `tasks/control-plane.yml:13` and `tasks/worker.yml:11`
2. `k3sup_onepassword_sdk_token` - **UNUSED** (should be removed)

## Required Action

1. **Decrypt the file** (requires working 1Password CLI integration):
   ```bash
   cd ansible
   ansible-vault decrypt roles/k3sup/vars/main.yml
   ```

2. **Edit the file** to remove the unused variable:
   ```bash
   # Remove these lines (approximately lines 18-30):
   k3sup_onepassword_sdk_token: !vault |
   [encrypted content]
   ```

3. **Keep only** the `k3sup_packages` variable (lines 5-16)

4. **Re-encrypt the file**:
   ```bash
   ansible-vault encrypt roles/k3sup/vars/main.yml
   ```

## Alternative: Migrate to Vault

Since we're migrating away from ansible-vault to HashiCorp Vault, consider:

1. **Decrypt** `ansible/roles/k3sup/vars/main.yml`
2. **Move** `k3sup_packages` value to Vault at `secret/fzymgc-house/infrastructure/k3sup/packages`
3. **Update** references in task files to use Vault lookup:
   ```yaml
   name: "{{ lookup('community.hashi_vault.vault_kv2_get', 'infrastructure/k3sup/packages', engine_mount_point='secret/fzymgc-house').secret.packages }}"
   ```
4. **Delete** the encrypted `vars/main.yml` file entirely

## Why This Matters

- Reduces complexity in the codebase
- Removes unused secrets that could confuse future developers
- Aligns with the migration to Vault for secrets management
- Simplifies ansible-vault decryption requirements

## Status

**Blocked**: Cannot decrypt the file without working 1Password CLI integration (used by `/Users/sean/bin/op-ansible-vault` password script).

Once 1Password integration is working again, or after migrating to Vault-based secrets, this cleanup can be completed.
