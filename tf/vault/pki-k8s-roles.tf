# -*- coding: utf-8; mode: terraform -*-
# SPDX-License-Identifier: MIT
#
# PKI roles for Kubernetes client certificate issuance.
# Each role has a fixed Organization field that maps to K8s RBAC groups.
#
# Usage: Users request certificates from these roles via Vault PKI.
# The Organization field becomes the K8s group for RBAC authorization.
# The Common Name (supplied at request time) becomes the K8s username.

# =============================================================================
# Admin Role - Full cluster access
# =============================================================================
# Issues certificates for cluster administrators with full access.
# Maps to 'k8s-admins' group in Kubernetes RBAC.

resource "vault_pki_secret_backend_role" "k8s_admin" {
  backend = "fzymgc-house/v1/ica1/v1"
  name    = "k8s-admin"

  # Allowed subject names - users authenticate as user@fzymgc.house
  allowed_domains    = ["fzymgc.house"]
  allow_bare_domains = true
  allow_subdomains   = false

  # Extended Key Usage: clientAuth only
  server_flag = false
  client_flag = true

  # Key configuration: ECDSA P-256
  key_type = "ec"
  key_bits = 256

  # Certificate TTL: 8 hours default, 24 hours max
  ttl     = "8h"
  max_ttl = "24h"

  # Fixed organization - maps to K8s group
  organization = ["k8s-admins"]

  # Disable hostname enforcement for client certs
  allow_any_name    = false
  enforce_hostnames = false
}

# =============================================================================
# Developer Role - Read/write workloads
# =============================================================================
# Issues certificates for developers who need to deploy and manage workloads.
# Maps to 'k8s-developers' group in Kubernetes RBAC.

resource "vault_pki_secret_backend_role" "k8s_developer" {
  backend = "fzymgc-house/v1/ica1/v1"
  name    = "k8s-developer"

  allowed_domains    = ["fzymgc.house"]
  allow_bare_domains = true
  allow_subdomains   = false

  server_flag = false
  client_flag = true

  key_type = "ec"
  key_bits = 256

  ttl     = "8h"
  max_ttl = "24h"

  organization = ["k8s-developers"]

  allow_any_name    = false
  enforce_hostnames = false
}

# =============================================================================
# Viewer Role - Read-only access
# =============================================================================
# Issues certificates for read-only cluster access.
# Maps to 'k8s-viewers' group in Kubernetes RBAC.

resource "vault_pki_secret_backend_role" "k8s_viewer" {
  backend = "fzymgc-house/v1/ica1/v1"
  name    = "k8s-viewer"

  allowed_domains    = ["fzymgc.house"]
  allow_bare_domains = true
  allow_subdomains   = false

  server_flag = false
  client_flag = true

  key_type = "ec"
  key_bits = 256

  ttl     = "8h"
  max_ttl = "24h"

  organization = ["k8s-viewers"]

  allow_any_name    = false
  enforce_hostnames = false
}
