# Scripts Directory

Utility scripts for managing the selfhosted cluster infrastructure.

## Vault Management

### vault-helper.sh

Helper script for common Vault operations with infrastructure secrets.

```bash
# Check Vault status and authentication
./vault-helper.sh status

# Authenticate to Vault
./vault-helper.sh login

# List all infrastructure secrets
./vault-helper.sh list

# Get a specific secret
./vault-helper.sh get bmc/tpi-alpha
./vault-helper.sh get bmc/tpi-alpha password  # Get just the password field

# Create or update a secret
./vault-helper.sh put bmc/tpi-alpha password="newpassword"

# Delete a secret (with confirmation)
./vault-helper.sh delete test/secret
```

All paths are relative to `secret/fzymgc-house/infrastructure/`.

### migrate-secrets-to-vault.sh

One-time migration script to move secrets from 1Password and .envrc to Vault.

```bash
# Run the migration (requires 1Password CLI and Vault authentication)
./migrate-secrets-to-vault.sh
```

This script:
1. Extracts secrets from .envrc and 1Password
2. Creates them in Vault at `secret/fzymgc-house/infrastructure/*`
3. Verifies the secrets were created successfully
4. Provides guidance for handling ansible-vault encrypted files

**Note:** This is a one-time migration script. After migration is complete, secrets should be managed directly in Vault.

## Usage

Make sure scripts are executable:

```bash
chmod +x scripts/*.sh
```

Most scripts require Vault authentication. Run `vault login` first if not already authenticated.
