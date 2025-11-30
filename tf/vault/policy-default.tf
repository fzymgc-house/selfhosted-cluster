import {
  id = "default"
  to = vault_policy.default
}

resource "vault_policy" "default" {
  name   = "default"
  policy = <<EOT
# =============================================================================
# Token Self-Management
# =============================================================================

# Allow tokens to look up their own properties
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Allow tokens to renew themselves
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Allow tokens to revoke themselves
path "auth/token/revoke-self" {
  capabilities = ["update"]
}

# Allow a token to look up its own capabilities on a path
path "sys/capabilities-self" {
  capabilities = ["update"]
}

# =============================================================================
# Identity Management
# =============================================================================

# Allow a token to look up its own entity by id or name
path "identity/entity/id/{{identity.entity.id}}" {
  capabilities = ["read"]
}

path "identity/entity/name/{{identity.entity.name}}" {
  capabilities = ["read"]
}

# Allow a token to make requests to the Authorization Endpoint for OIDC providers
path "identity/oidc/provider/+/authorize" {
  capabilities = ["read", "update"]
}

# =============================================================================
# UI Support
# =============================================================================

# Allow a token to look up its resultant ACL from all policies
# Required for Vault UI to function properly
path "sys/internal/ui/resultant-acl" {
  capabilities = ["read"]
}

# Allow listing of visible mounts for UI navigation
path "sys/internal/ui/mounts" {
  capabilities = ["read"]
}

# =============================================================================
# Lease Management
# =============================================================================

# Allow a token to renew a lease via lease_id in the request body
# Old path for old clients, new path for newer
path "sys/renew" {
  capabilities = ["update"]
}

path "sys/leases/renew" {
  capabilities = ["update"]
}

# Allow looking up lease properties (requires knowing the lease ID)
path "sys/leases/lookup" {
  capabilities = ["update"]
}

# =============================================================================
# Cubbyhole
# =============================================================================

# Allow a token to manage its own cubbyhole (personal secret storage)
path "cubbyhole/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# =============================================================================
# Response Wrapping
# =============================================================================

# Allow a token to wrap arbitrary values in a response-wrapping token
path "sys/wrapping/wrap" {
  capabilities = ["update"]
}

# Allow a token to look up the creation time and TTL of a response-wrapping token
path "sys/wrapping/lookup" {
  capabilities = ["update"]
}

# Allow a token to unwrap a response-wrapping token
path "sys/wrapping/unwrap" {
  capabilities = ["update"]
}

# =============================================================================
# General Purpose Tools
# =============================================================================

# Allow hashing data
path "sys/tools/hash" {
  capabilities = ["update"]
}

path "sys/tools/hash/*" {
  capabilities = ["update"]
}

# Allow generating random bytes
path "sys/tools/random" {
  capabilities = ["update"]
}

path "sys/tools/random/*" {
  capabilities = ["update"]
}

# =============================================================================
# Password Policies
# =============================================================================

# Allow generating passwords using configured password policies
path "sys/policies/password/+/generate" {
  capabilities = ["read"]
}

# =============================================================================
# Control Groups (Enterprise)
# =============================================================================

# Allow checking the status of a Control Group request
path "sys/control-group/request" {
  capabilities = ["update"]
}

# =============================================================================
# Internal PKI - Public Certificate Access
# These paths provide read access to public CA certificates and CRLs
# =============================================================================

# CA certificate endpoints
path "fzymgc-house/v1/ica1/v1/ca" {
  capabilities = ["read"]
}

path "fzymgc-house/v1/ica1/v1/ca/pem" {
  capabilities = ["read"]
}

path "fzymgc-house/v1/ica1/v1/ca_chain" {
  capabilities = ["read"]
}

# Certificate Revocation List (CRL) endpoints
path "fzymgc-house/v1/ica1/v1/crl" {
  capabilities = ["read"]
}

path "fzymgc-house/v1/ica1/v1/crl/pem" {
  capabilities = ["read"]
}

path "fzymgc-house/v1/ica1/v1/crl/delta" {
  capabilities = ["read"]
}

path "fzymgc-house/v1/ica1/v1/crl/delta/pem" {
  capabilities = ["read"]
}

# Issuer information
path "fzymgc-house/v1/ica1/v1/issuers" {
  capabilities = ["list"]
}

path "fzymgc-house/v1/ica1/v1/issuer/+/json" {
  capabilities = ["read"]
}

path "fzymgc-house/v1/ica1/v1/issuer/+/pem" {
  capabilities = ["read"]
}

EOT
}
