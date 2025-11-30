resource "vault_policy" "admin" {
  name   = "admin"
  policy = <<EOT
# =============================================================================
# Vault Administrator Policy
# =============================================================================
# Purpose: Comprehensive administrative access to Vault
# Usage: Attach to admin group for full Vault management capabilities
# Note: This does NOT grant root access - some operations still require root token

# =============================================================================
# Policy Management
# =============================================================================

# Manage all policies
path "sys/policies/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/policies" {
  capabilities = ["list"]
}

# Legacy policy path
path "sys/policy/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/policy" {
  capabilities = ["list"]
}

# =============================================================================
# Auth Backend Management
# =============================================================================

# List and manage auth methods
path "sys/auth" {
  capabilities = ["read", "list", "sudo"]
}

path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Configure all auth backends
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# =============================================================================
# Secret Engine Management
# =============================================================================

# List and manage secret engines
path "sys/mounts" {
  capabilities = ["read", "list"]
}

path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Tune mount configurations
path "sys/mounts/+/tune" {
  capabilities = ["read", "update"]
}

# =============================================================================
# Secret Management
# =============================================================================

# Full access to KV secrets engine
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/+/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Metadata management for KV v2
path "secret/metadata/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/delete/*" {
  capabilities = ["update"]
}

path "secret/undelete/*" {
  capabilities = ["update"]
}

path "secret/destroy/*" {
  capabilities = ["update"]
}

# =============================================================================
# Identity Management
# =============================================================================

# Full control over identity secrets engine
path "identity/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "identity" {
  capabilities = ["list"]
}

# =============================================================================
# Token Management
# =============================================================================

# Create and manage tokens
path "auth/token/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Create child tokens
path "auth/token/create" {
  capabilities = ["create", "update", "sudo"]
}

# Create orphan tokens
path "auth/token/create-orphan" {
  capabilities = ["create", "update", "sudo"]
}

# Lookup tokens
path "auth/token/lookup" {
  capabilities = ["read", "update"]
}

path "auth/token/lookup-accessor" {
  capabilities = ["read", "update"]
}

# Revoke tokens
path "auth/token/revoke" {
  capabilities = ["update"]
}

path "auth/token/revoke-accessor" {
  capabilities = ["update"]
}

path "auth/token/revoke-orphan" {
  capabilities = ["update"]
}

# =============================================================================
# Lease Management
# =============================================================================

# Manage leases
path "sys/leases/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "sys/leases" {
  capabilities = ["list"]
}

# Revoke leases
path "sys/leases/revoke" {
  capabilities = ["update"]
}

path "sys/leases/revoke-prefix/*" {
  capabilities = ["update", "sudo"]
}

path "sys/leases/revoke-force/*" {
  capabilities = ["update", "sudo"]
}

# =============================================================================
# Audit Management
# =============================================================================

# List and manage audit devices
path "sys/audit" {
  capabilities = ["read", "list", "sudo"]
}

path "sys/audit/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "sys/audit-hash/*" {
  capabilities = ["create", "update"]
}

# =============================================================================
# System Health & Status
# =============================================================================

# Read system health
path "sys/health" {
  capabilities = ["read", "sudo"]
}

# Read seal status
path "sys/seal-status" {
  capabilities = ["read"]
}

# Read cluster info
path "sys/leader" {
  capabilities = ["read"]
}

path "sys/ha-status" {
  capabilities = ["read"]
}

path "sys/host-info" {
  capabilities = ["read"]
}

# Read storage backend status
path "sys/storage/raft/status" {
  capabilities = ["read"]
}

path "sys/storage/raft/configuration" {
  capabilities = ["read"]
}

# =============================================================================
# Configuration Management
# =============================================================================

# Read and update Vault configuration
path "sys/config/*" {
  capabilities = ["read", "update", "list"]
}

# Manage namespaces (Enterprise)
path "sys/namespaces/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# =============================================================================
# Capabilities & ACL Testing
# =============================================================================

# Check capabilities
path "sys/capabilities" {
  capabilities = ["create", "update"]
}

path "sys/capabilities-accessor" {
  capabilities = ["create", "update"]
}

# =============================================================================
# PKI Management
# =============================================================================

# Full access to PKI secrets engines
path "fzymgc-house/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# =============================================================================
# Metrics & Telemetry
# =============================================================================

# Read metrics
path "sys/metrics" {
  capabilities = ["read"]
}

# =============================================================================
# Internal UI Paths
# =============================================================================

# Required for Vault UI functionality
path "sys/internal/ui/*" {
  capabilities = ["read"]
}

path "sys/internal/counters/*" {
  capabilities = ["read"]
}

# =============================================================================
# Replication (Enterprise)
# =============================================================================

path "sys/replication/*" {
  capabilities = ["read", "list"]
}

# =============================================================================
# Tools
# =============================================================================

# Generate random bytes
path "sys/tools/random/*" {
  capabilities = ["update"]
}

# Hash data
path "sys/tools/hash/*" {
  capabilities = ["update"]
}

# =============================================================================
# Wrapping
# =============================================================================

# Wrap and unwrap responses
path "sys/wrapping/*" {
  capabilities = ["create", "read", "update"]
}
EOT
}
