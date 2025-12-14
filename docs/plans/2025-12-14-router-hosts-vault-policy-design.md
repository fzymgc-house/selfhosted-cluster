# Router-Hosts Vault Policy Design

## Summary

Configure Vault to support router-hosts mTLS certificate management via vault-agent on a VM outside the Kubernetes cluster.

## Context

Router-hosts requires mTLS certificates for secure gRPC communication. The [router-hosts examples](https://github.com/fzymgc-house/router-hosts/tree/main/examples) demonstrate vault-agent with AppRole authentication for automatic certificate renewal.

This design creates the Vault resources needed to support that deployment pattern.

## Components

| Component | Terraform File | Purpose |
|-----------|----------------|---------|
| PKI Role: `router-hosts-server` | `pki-router-hosts.tf` | Issue server certificates |
| PKI Role: `router-hosts-client` | `pki-router-hosts.tf` | Issue client certificates |
| Policy: `router-hosts` | `policy-router-hosts.tf` | Grant certificate issuance access |
| AppRole: `router-hosts-agent` | `approle-router-hosts.tf` | Authenticate vault-agent |

## PKI Roles

### router-hosts-server

Issues server certificates for mTLS server authentication.

| Setting | Value |
|---------|-------|
| `allowed_domains` | `localhost`, `router.fzymgc.house`, `router`, `router.local` |
| `allow_bare_domains` | `true` |
| `allow_subdomains` | `false` |
| `allow_ip_sans` | `true` |
| `allowed_uri_sans` | (none) |
| `server_flag` | `true` |
| `client_flag` | `false` |
| `key_type` | `ec` |
| `key_bits` | `256` (P-256) |
| `ttl` | `720h` (30 days) |
| `max_ttl` | `720h` (30 days) |

**Expected IP SANs:** `127.0.0.1`, `192.168.20.1` (see Security Considerations)

### router-hosts-client

Issues client certificates for mTLS client authentication.

| Setting | Value |
|---------|-------|
| `allow_any_name` | `true` |
| `enforce_hostnames` | `false` |
| `server_flag` | `false` |
| `client_flag` | `true` |
| `key_type` | `ec` |
| `key_bits` | `256` (P-256) |
| `ttl` | `2160h` (90 days) |
| `max_ttl` | `2160h` (90 days) |

## Vault Policy

**Name:** `router-hosts`

```hcl
# Issue server certificates
path "fzymgc-house/v1/ica1/v1/issue/router-hosts-server" {
  capabilities = ["create", "update"]
}

# Issue client certificates
path "fzymgc-house/v1/ica1/v1/issue/router-hosts-client" {
  capabilities = ["create", "update"]
}

# Sign CSRs (alternative to issue)
path "fzymgc-house/v1/ica1/v1/sign/router-hosts-server" {
  capabilities = ["create", "update"]
}

path "fzymgc-house/v1/ica1/v1/sign/router-hosts-client" {
  capabilities = ["create", "update"]
}

# Read CA certificate chain
path "fzymgc-house/v1/ica1/v1/cert/ca" {
  capabilities = ["read"]
}

path "fzymgc-house/v1/ica1/v1/ca_chain" {
  capabilities = ["read"]
}

# Token self-management
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
```

## AppRole Configuration

**Name:** `router-hosts-agent`

| Setting | Value | Rationale |
|---------|-------|-----------|
| `token_policies` | `["router-hosts"]` | Grants policy above |
| `token_ttl` | `3600` (1 hour) | Short-lived tokens |
| `token_max_ttl` | `86400` (24 hours) | Maximum renewal window |
| `secret_id_ttl` | `0` | Never expires |
| `secret_id_num_uses` | `0` | Unlimited uses |

## Implementation

### Terraform Files

Create three files in `tf/vault/`:

1. **`pki-router-hosts.tf`** - PKI role definitions
2. **`policy-router-hosts.tf`** - Policy definition
3. **`approle-router-hosts.tf`** - AppRole configuration

### Post-Apply Steps

1. Retrieve AppRole credentials:
   ```bash
   vault read auth/approle/role/router-hosts-agent/role-id
   vault write -f auth/approle/role/router-hosts-agent/secret-id
   ```

2. Store credentials securely on router host

3. Configure vault-agent using the router-hosts example config, adjusted for:
   - Vault address: `https://vault.fzymgc.house`
   - PKI path: `fzymgc-house/v1/ica1/v1/issue/router-hosts-server`

## Security Considerations

- **Minimal permissions:** Policy grants only certificate issuance, no revocation or role management
- **Short token TTL:** 1-hour tokens limit exposure if compromised
- **Non-expiring secret_id:** Acceptable for long-running services; rotate manually if compromised
- **Response wrapping:** Consider wrapping secret_id when retrieving for production deployment
- **IP SAN limitation:** Vault PKI roles cannot restrict which IP addresses are allowed in SANs—`allow_ip_sans = true` permits any IP. The security boundary is enforced by vault-agent's certificate request configuration, which should specify only the expected IPs (`127.0.0.1`, `192.168.20.1`)
