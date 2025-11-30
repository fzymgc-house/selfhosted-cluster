# Vault Migration - Quick Start

This repository has migrated from 1Password to HashiCorp Vault for secrets management.

## For Developers

### Prerequisites

1. **Vault CLI installed:**
   ```bash
   brew install vault
   ```

2. **Vault token with `infrastructure-developer` policy**
   - Contact your Vault administrator to get a token
   - Or use GitHub/OIDC auth if configured

### Setup

1. **Authenticate to Vault:**
   ```bash
   export VAULT_ADDR=https://vault.fzymgc.house
   vault login
   # Enter your token or use configured auth method
   ```

2. **Verify access:**
   ```bash
   # Check your token has the right policy
   vault token lookup

   # Test reading a secret
   vault kv get secret/fzymgc-house/infrastructure/bmc/tpi-alpha
   ```

3. **Use Ansible/Terraform as normal:**
   ```bash
   # Ansible will automatically retrieve secrets from Vault
   cd ansible
   source .venv/bin/activate
   ansible-playbook -i inventory/hosts.yml playbook.yml

   # Terraform will automatically use your Vault token
   cd tf/authentik
   terraform plan
   ```

### Helper Script

Use the vault-helper script for common operations:

```bash
# Check Vault status
./scripts/vault-helper.sh status

# List all infrastructure secrets
./scripts/vault-helper.sh list

# Get a specific secret
./scripts/vault-helper.sh get bmc/tpi-alpha
./scripts/vault-helper.sh get bmc/tpi-alpha password  # Just the password field

# See all commands
./scripts/vault-helper.sh help
```

## For Vault Administrators

### Creating the Infrastructure Developer Policy

1. **Create the policy in Vault:**
   ```bash
   cd tf/vault
   vault policy write infrastructure-developer policy-infrastructure-developer.hcl
   ```

2. **Create tokens for developers:**
   ```bash
   # Create a token with the policy
   vault token create -policy=infrastructure-developer -ttl=720h
   ```

   Or configure GitHub/OIDC auth to automatically attach the policy.

### Migrating Secrets (One-Time)

If you're the person performing the initial migration:

1. **Run the migration script:**
   ```bash
   ./scripts/migrate-secrets-to-vault.sh
   ```

   This extracts secrets from .envrc and 1Password and creates them in Vault.

2. **Manually migrate ansible-vault encrypted files:**
   ```bash
   cd ansible
   ansible-vault view roles/k3sup/vars/main.yml
   # Create each secret in Vault manually
   ```

See `docs/vault-migration.md` for complete migration instructions.

## What Changed

### Removed Dependencies
- ❌ 1Password CLI (`op`) no longer required
- ❌ 1Password account not needed
- ❌ Secrets in `.envrc` removed
- ❌ ansible-vault password file removed

### New Requirements
- ✅ Vault CLI required
- ✅ Valid Vault token with `infrastructure-developer` policy
- ✅ Network access to `https://vault.fzymgc.house`

### How Secrets Are Retrieved

**Before (1Password):**
```yaml
# Ansible
cloudflare_api_token: "{{ lookup('community.general.onepassword', 'cloudflare-api-token', vault='fzymgc-house', field='password') }}"

# Environment
source .envrc  # Contains hardcoded passwords
```

**After (Vault):**
```yaml
# Ansible
cloudflare_api_token: "{{ lookup('community.hashi_vault.vault_kv2_get', 'infrastructure/cloudflare/api-token', engine_mount_point='secret/fzymgc-house').secret.token }}"

# Environment
export VAULT_ADDR=https://vault.fzymgc.house
vault login  # Authenticate once, token saved to ~/.vault-token
```

## Troubleshooting

### "Permission denied" errors

Your token doesn't have the `infrastructure-developer` policy. Contact your Vault administrator.

```bash
# Check your policies
vault token lookup
```

### "Connection refused" to Vault

Ensure you're on the VPN or have network access to `vault.fzymgc.house`:

```bash
curl https://vault.fzymgc.house/v1/sys/health
```

### Ansible can't find secrets

1. Verify Vault authentication:
   ```bash
   vault token lookup
   ```

2. Test the lookup manually:
   ```bash
   vault kv get secret/fzymgc-house/infrastructure/cloudflare/api-token
   ```

3. Ensure the `community.hashi_vault` Ansible collection is installed:
   ```bash
   ansible-galaxy collection list | grep hashi_vault
   ```

## Documentation

- **Quick Start:** This file
- **Complete Migration Guide:** `docs/vault-migration.md`
- **Migration Summary:** `docs/vault-migration-summary.md`
- **Policy File:** `tf/vault/policy-infrastructure-developer.hcl`
- **Helper Scripts:** `scripts/README.md`

## Questions?

See the full documentation in `docs/vault-migration.md` or contact your Vault administrator.
