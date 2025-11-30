resource "vault_policy" "reader" {
  name   = "reader"
  policy = <<EOT
# =============================================================================
# Vault Reader Policy
# =============================================================================
# Purpose: Browse secrets metadata and view system information (no secret values)
# Usage: Attach to reader group for users who need visibility without secret access
# Note: To read actual secret values, grant additional policies (e.g., infrastructure-developer)

# =============================================================================
# Secret Browsing (Metadata Only)
# =============================================================================

# List and browse secret paths (metadata only, not actual secret values)
# Users needing to read specific secrets should be granted additional policies
path "secret/metadata" {
  capabilities = ["list"]
}

path "secret/metadata/*" {
  capabilities = ["list"]
}

# =============================================================================
# Auth Information
# =============================================================================

# List auth methods (no sensitive data)
path "sys/auth" {
  capabilities = ["read"]
}

# =============================================================================
# Mount Information
# =============================================================================

# List secret engines
path "sys/mounts" {
  capabilities = ["read"]
}

# =============================================================================
# Policy Information
# =============================================================================

# List and read policies
path "sys/policies/acl" {
  capabilities = ["list"]
}

path "sys/policies/acl/*" {
  capabilities = ["read"]
}

# Legacy policy path
path "sys/policy" {
  capabilities = ["list"]
}

path "sys/policy/*" {
  capabilities = ["read"]
}

# =============================================================================
# Identity Information
# =============================================================================

# Read identity entities (limited to self via default policy)
path "identity/entity/id/*" {
  capabilities = ["read"]
}

path "identity/entity/name/*" {
  capabilities = ["read"]
}

# List groups
path "identity/group/id/*" {
  capabilities = ["read"]
}

path "identity/group/name/*" {
  capabilities = ["read"]
}

# =============================================================================
# System Health (Public Info)
# =============================================================================

# Read system health
path "sys/health" {
  capabilities = ["read"]
}

# Read seal status
path "sys/seal-status" {
  capabilities = ["read"]
}

# Read leader info
path "sys/leader" {
  capabilities = ["read"]
}

# =============================================================================
# PKI Public Information
# =============================================================================

# Read CA certificates and CRLs (public data)
path "fzymgc-house/v1/ica1/v1/ca" {
  capabilities = ["read"]
}

path "fzymgc-house/v1/ica1/v1/ca/pem" {
  capabilities = ["read"]
}

path "fzymgc-house/v1/ica1/v1/ca_chain" {
  capabilities = ["read"]
}

path "fzymgc-house/v1/ica1/v1/crl" {
  capabilities = ["read"]
}

path "fzymgc-house/v1/ica1/v1/crl/pem" {
  capabilities = ["read"]
}

# List issuers
path "fzymgc-house/v1/ica1/v1/issuers" {
  capabilities = ["list"]
}

path "fzymgc-house/v1/ica1/v1/issuer/+/json" {
  capabilities = ["read"]
}

path "fzymgc-house/v1/ica1/v1/issuer/+/pem" {
  capabilities = ["read"]
}

# =============================================================================
# Internal UI Paths
# =============================================================================

# Required for Vault UI navigation
path "sys/internal/ui/mounts" {
  capabilities = ["read"]
}

path "sys/internal/ui/mounts/*" {
  capabilities = ["read"]
}
EOT
}
