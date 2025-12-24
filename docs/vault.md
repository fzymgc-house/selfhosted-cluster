# Vault

HashiCorp Vault for infrastructure secrets management.

## Secret Structure

All infrastructure secrets stored under `secret/fzymgc-house/`:

| Path | Purpose |
|------|---------|
| `infrastructure/bmc/tpi-alpha` | TuringPi Alpha BMC credentials |
| `infrastructure/bmc/tpi-beta` | TuringPi Beta BMC credentials |
| `infrastructure/cloudflare/api-token` | Cloudflare API token |
| `cluster/authentik` | Authentik Terraform token |
| `cluster/windmill` | Windmill secrets (Discord, S3, tokens) |

## Developer Workflow

```bash
# Authenticate
export VAULT_ADDR=https://vault.fzymgc.house
vault login

# Helper script operations
./scripts/vault-helper.sh status              # Check connectivity
./scripts/vault-helper.sh list                # List infrastructure secrets
./scripts/vault-helper.sh get bmc/tpi-alpha   # Get specific secret
./scripts/vault-helper.sh get bmc/tpi-alpha password  # Single field
```

## Ansible Integration

```yaml
# Vault lookup in group_vars
tpi_bmc_password: "{{ lookup('community.hashi_vault.vault_kv2_get', 'infrastructure/bmc/tpi-alpha', engine_mount_point='secret/fzymgc-house').secret.password }}"

cloudflare_api_token: "{{ lookup('community.hashi_vault.vault_kv2_get', 'infrastructure/cloudflare/api-token', engine_mount_point='secret/fzymgc-house').secret.token }}"
```

Requires `community.hashi_vault` collection (installed via requirements).

## Terraform Integration

```hcl
data "vault_kv_secret_v2" "cloudflare" {
  mount = "secret/fzymgc-house"
  name  = "infrastructure/cloudflare/api-token"
}

provider "cloudflare" {
  api_token = data.vault_kv_secret_v2.cloudflare.data["token"]
}
```

## Required Policy

Developers need `infrastructure-developer` policy. Defined in `tf/vault/policy-infrastructure-developer.hcl`:

```hcl
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

## Troubleshooting

### Connectivity
```bash
curl -s https://vault.fzymgc.house/v1/sys/health
vault token lookup
```

### Ansible Secret Issues
```bash
ansible-galaxy collection list | grep hashi_vault
ansible localhost -m debug -a "msg={{ lookup('community.hashi_vault.vault_kv2_get', 'infrastructure/bmc/tpi-alpha', engine_mount_point='secret/fzymgc-house').secret.password }}"
```

### Terraform Issues
```bash
vault token lookup
terraform console
> data.vault_kv_secret_v2.authentik.data
```
