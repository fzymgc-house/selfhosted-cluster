# -*- coding: utf-8; mode: terraform -*-
# SPDX-License-Identifier: MIT
#
# PKI roles for router-hosts mTLS certificate issuance.
# These roles define certificate templates for server and client authentication.
#
# See: https://github.com/fzymgc-house/router-hosts/tree/main/examples

# =============================================================================
# Server Certificate Role
# =============================================================================
# Issues certificates with serverAuth extended key usage for mTLS server auth.

resource "vault_pki_secret_backend_role" "router_hosts_server" {
  backend = "fzymgc-house/v1/ica1/v1"
  name    = "router-hosts-server"

  # Allowed subject names
  allowed_domains    = ["localhost", "router.fzymgc.house", "router", "router.local"]
  allow_bare_domains = true
  allow_subdomains   = false
  allow_localhost    = true

  # IP SANs for direct IP access
  allow_ip_sans    = true
  allowed_uri_sans = []

  # Extended Key Usage: serverAuth only
  server_flag = true
  client_flag = false

  # Key configuration: ECDSA P-256
  key_type = "ec"
  key_bits = 256

  # Certificate TTL: 30 days (auto-renewed by vault-agent)
  ttl     = "720h"
  max_ttl = "720h"

  # Allow any organization/OU in CSR
  allow_any_name    = false
  enforce_hostnames = true
}

# =============================================================================
# Client Certificate Role
# =============================================================================
# Issues certificates with clientAuth extended key usage for mTLS client auth.

resource "vault_pki_secret_backend_role" "router_hosts_client" {
  backend = "fzymgc-house/v1/ica1/v1"
  name    = "router-hosts-client"

  # Allow flexible client identities
  allow_any_name    = true
  enforce_hostnames = false

  # Extended Key Usage: clientAuth only
  server_flag = false
  client_flag = true

  # Key configuration: ECDSA P-256
  key_type = "ec"
  key_bits = 256

  # Certificate TTL: 90 days (longer for manually-managed client certs)
  ttl     = "2160h"
  max_ttl = "2160h"
}
