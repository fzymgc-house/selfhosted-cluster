# -*- coding: utf-8; mode: terraform -*-
# SPDX-License-Identifier: MIT
#
# Vault policy for router-hosts vault-agent.
# Grants certificate issuance from PKI and token self-management.
#
# See: https://github.com/fzymgc-house/router-hosts/tree/main/examples

resource "vault_policy" "router_hosts" {
  name   = "router-hosts"
  policy = <<EOT

# =============================================================================
# PKI Certificate Issuance
# =============================================================================

# Issue server certificates (mTLS server authentication)
path "fzymgc-house/v1/ica1/v1/issue/router-hosts-server" {
  capabilities = ["create", "update"]
}

# Issue client certificates (mTLS client authentication)
path "fzymgc-house/v1/ica1/v1/issue/router-hosts-client" {
  capabilities = ["create", "update"]
}

# Sign CSRs (alternative to issue endpoint)
path "fzymgc-house/v1/ica1/v1/sign/router-hosts-server" {
  capabilities = ["create", "update"]
}

path "fzymgc-house/v1/ica1/v1/sign/router-hosts-client" {
  capabilities = ["create", "update"]
}

# =============================================================================
# CA Certificate Access
# =============================================================================

# Read CA certificate
path "fzymgc-house/v1/ica1/v1/cert/ca" {
  capabilities = ["read"]
}

# Read full CA chain
path "fzymgc-house/v1/ica1/v1/ca_chain" {
  capabilities = ["read"]
}

# =============================================================================
# Token Self-Management
# =============================================================================

# Renew own token (required for vault-agent auto-auth)
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Lookup own token information
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

EOT
}
