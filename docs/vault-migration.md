# Vault Secrets Migration Guide

This guide documents the migration from 1Password-based secrets to HashiCorp Vault for infrastructure automation.

## Overview

**Goal**: Remove dependency on 1Password CLI and store all infrastructure secrets in Vault.

**Affected Systems**:
- Ansible playbooks (BMC passwords, Cloudflare API tokens, Vault tokens)
- Terraform modules (removing onepassword provider)
- Development environment (.envrc, devcontainer)

## Secret Inventory

### Secrets to Migrate

| Secret | Current Location | New Vault Path | Format |
|--------|-----------------|----------------|--------|
| TuringPi Alpha BMC Password | .envrc | `secret/fzymgc-house/infrastructure/bmc/tpi-alpha` | `{password: "..."}` |
| TuringPi Beta BMC Password | .envrc | `secret/fzymgc-house/infrastructure/bmc/tpi-beta` | `{password: "..."}` |
| Cloudflare API Token | 1Password → Ansible | `secret/fzymgc-house/infrastructure/cloudflare/api-token` | `{token: "..."}` |
| Ansible Vault Password | 1Password | ~~Not migrating - eliminating ansible-vault~~ | N/A |
| k3sup vars (ansible-vault encrypted) | ansible/roles/k3sup/vars/main.yml | `secret/fzymgc-house/infrastructure/k3sup/*` | TBD based on contents |
| SOPS Age Key | ~/.config/age-keys.txt | (Optional) `secret/fzymgc-house/infrastructure/sops/age-key` | `{private_key: "..."}` |

### Secrets NOT Migrating to Vault

| Secret | Reason | Alternative |
|--------|--------|-------------|
| Vault Root Token | Cannot store root token in Vault itself | Developers must authenticate with their own Vault token (see Required Vault Policy below) |

### Secrets Already in Vault

These are already stored in Vault and don't need migration:
- Authentik Terraform token: `secret/fzymgc-house/authentik` (used by tf/authentik)
- Application secrets: `secret/fzymgc-house/*` (used by ExternalSecrets)

## Required Vault Policy for Developers

Developers need a Vault token with a policy that allows reading infrastructure secrets. The Vault root token **cannot** be stored in Vault itself, so each developer must authenticate with their own token.

### Required Policy

Create a Vault policy named `infrastructure-developer` with the following permissions:

```hcl
# Policy: infrastructure-developer
# Purpose: Allow developers to read infrastructure secrets for Ansible and Terraform

# Read infrastructure secrets
path "secret/data/fzymgc-house/infrastructure/*" {
  capabilities = ["read", "list"]
}

# List infrastructure secret paths
path "secret/metadata/fzymgc-house/infrastructure/*" {
  capabilities = ["list"]
}

# Read application secrets (used by Terraform)
path "secret/data/fzymgc-house/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/fzymgc-house/*" {
  capabilities = ["list"]
}
```

### Creating the Policy

As a Vault administrator with root or admin privileges:

```bash
# Create policy file
cat > infrastructure-developer-policy.hcl <<'EOF'
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
EOF

# Create the policy in Vault
vault policy write infrastructure-developer infrastructure-developer-policy.hcl
```

### Developer Authentication

Developers should authenticate using one of these methods:

1. **Token Auth (simplest for development):**
   ```bash
   vault login
   # Enter your personal token with infrastructure-developer policy
   ```

2. **GitHub Auth (recommended):**
   ```bash
   vault login -method=github
   # Enter your GitHub personal access token
   ```

3. **OIDC/LDAP Auth (if configured):**
   ```bash
   vault login -method=oidc
   ```

After authentication, the token is saved to `~/.vault-token` and will be automatically used by Ansible and Terraform.

## Migration Steps

### Step 1: Extract Secrets from Current Sources

Run these commands to extract the secrets you'll need to add to Vault:

```bash
# 1. Get BMC passwords from .envrc
source .envrc
echo "TPI Alpha BMC: $TPI_ALPHA_BMC_ROOT_PW"
echo "TPI Beta BMC: $TPI_BETA_BMC_ROOT_PW"

# 2. Get secrets from 1Password
op item get --vault fzymgc-house "cloudflare-api-token" --fields password

# 3. Decrypt ansible-vault encrypted file
cd ansible
ansible-vault view roles/k3sup/vars/main.yml
```

### Step 2: Create Secrets in Vault

Use the provided script `scripts/migrate-secrets-to-vault.sh` or manually create:

```bash
# Authenticate to Vault
export VAULT_ADDR=https://vault.fzymgc.house
vault login

# Create BMC secrets
vault kv put secret/fzymgc-house/infrastructure/bmc/tpi-alpha password="<TPI_ALPHA_BMC_ROOT_PW>"
vault kv put secret/fzymgc-house/infrastructure/bmc/tpi-beta password="<TPI_BETA_BMC_ROOT_PW>"

# Create Cloudflare secret
vault kv put secret/fzymgc-house/infrastructure/cloudflare/api-token token="<CLOUDFLARE_API_TOKEN>"

# Create k3sup secrets (after decrypting ansible-vault file)
# vault kv put secret/fzymgc-house/infrastructure/k3sup/<secret-name> <key>=<value>
```

### Step 3: Verify Secrets in Vault

```bash
# List all infrastructure secrets
vault kv list secret/fzymgc-house/infrastructure/

# Read individual secrets to verify
vault kv get secret/fzymgc-house/infrastructure/bmc/tpi-alpha
vault kv get secret/fzymgc-house/infrastructure/cloudflare/api-token
```

### Step 4: Update Code (Automated)

The following files will be updated automatically:
- `ansible/inventory/group_vars/tpi_alpha_hosts.yml`
- `ansible/inventory/group_vars/tpi_beta_hosts.yml`
- `ansible/inventory/group_vars/tp_cluster_nodes.yml`
- `ansible/ansible.cfg` (remove vault_password_file)
- `tf/authentik/terraform.tf` (remove onepassword provider)
- `.envrc` (remove secrets)
- `.devcontainer/devcontainer.json` (remove 1Password agent)
- `.devcontainer/post-create.sh` (add vault login)

### Step 5: Test

```bash
# Test Ansible can retrieve secrets
cd ansible
ansible-playbook -i inventory/hosts.yml --check playbook.yml

# Test Terraform can access Vault
cd tf/authentik
terraform init
terraform plan
```

### Step 6: Cleanup

After verifying everything works:

```bash
# Remove old files
rm ansible/.ansible_vault_password
# Decrypt and delete ansible-vault encrypted file (migrate to Vault first!)
# rm ansible/roles/k3sup/vars/main.yml (after migration)

# Update .envrc to only contain non-secret config
# Commit changes
```

## Ansible Vault Lookup Examples

After migration, Ansible will use the `community.hashi_vault.vault_kv2_get` lookup:

```yaml
# Old (1Password)
cloudflare_api_token: "{{ lookup('community.general.onepassword', 'cloudflare-api-token', vault='fzymgc-house', field='password') }}"

# New (Vault)
cloudflare_api_token: "{{ lookup('community.hashi_vault.vault_kv2_get', 'infrastructure/cloudflare/api-token', engine_mount_point='secret/fzymgc-house').secret.token }}"
```

## Terraform Vault Data Source Examples

```hcl
# Read secret from Vault
data "vault_kv_secret_v2" "cloudflare" {
  mount = "secret/fzymgc-house"
  name  = "infrastructure/cloudflare/api-token"
}

# Use in provider
provider "cloudflare" {
  api_token = data.vault_kv_secret_v2.cloudflare.data["token"]
}
```

## Development Workflow Changes

### Old Workflow
1. Install 1Password CLI
2. Sign in to 1Password
3. Source .envrc with hardcoded secrets
4. Run ansible/terraform

### New Workflow
1. Start devcontainer: `./dev.sh shell`
2. Authenticate to Vault: `vault login` (prompted automatically)
3. Run ansible/terraform (secrets retrieved from Vault automatically)

## Rollback Plan

If migration fails:
1. Secrets remain in 1Password (not deleted)
2. Old .envrc can be restored from git history
3. ansible-vault password script can be restored
4. No data loss - only configuration changes

## Security Improvements

1. **No secrets in environment variables**: .envrc no longer contains passwords
2. **No secrets in git history**: Secrets never committed to repo
3. **Centralized secret management**: All secrets in Vault with audit logging
4. **Short-lived tokens**: Vault tokens expire, unlike static passwords in .envrc
5. **Reduced dependencies**: No 1Password CLI, agent, or account required

## Troubleshooting

### Vault connection issues
```bash
# Check Vault connectivity
curl -s https://vault.fzymgc.house/v1/sys/health

# Verify VAULT_ADDR
echo $VAULT_ADDR

# Check token validity
vault token lookup
```

### Ansible can't retrieve secrets
```bash
# Verify Ansible collection installed
ansible-galaxy collection list | grep hashi_vault

# Test Vault lookup manually
ansible localhost -m debug -a "msg={{ lookup('community.hashi_vault.vault_kv2_get', 'infrastructure/bmc/tpi-alpha', engine_mount_point='secret/fzymgc-house').secret.password }}"
```

### Terraform can't access Vault
```bash
# Check VAULT_TOKEN is set
vault token lookup

# Test Vault provider
cd tf/authentik
terraform console
> data.vault_kv_secret_v2.authentik.data
```
