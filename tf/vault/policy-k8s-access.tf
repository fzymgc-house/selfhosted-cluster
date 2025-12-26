# -*- coding: utf-8; mode: terraform -*-
# SPDX-License-Identifier: MIT
#
# Vault policies controlling which K8s PKI roles users can access.
# Each policy corresponds to an Authentik group.
#
# Permission model (cascading):
# - k8s-admin-cert: Can issue admin, developer, AND viewer certs (most privileged)
# - k8s-developer-cert: Can issue developer AND viewer certs
# - k8s-viewer-cert: Can only issue viewer certs (least privileged)
#
# All policies include ca_chain read access for kubeconfig generation.

# =============================================================================
# Admin Policy - Can issue all cert types
# =============================================================================

resource "vault_policy" "k8s_admin_cert" {
  name = "k8s-admin-cert"

  policy = <<EOT

# K8s admin can issue admin, developer, and viewer certs
path "fzymgc-house/v1/ica1/v1/issue/k8s-admin" {
  capabilities = ["create", "update"]
}
path "fzymgc-house/v1/ica1/v1/issue/k8s-developer" {
  capabilities = ["create", "update"]
}
path "fzymgc-house/v1/ica1/v1/issue/k8s-viewer" {
  capabilities = ["create", "update"]
}

# Read CA chain for kubeconfig
path "fzymgc-house/v1/ica1/v1/ca_chain" {
  capabilities = ["read"]
}

EOT
}

# =============================================================================
# Developer Policy - Can issue developer and viewer certs
# =============================================================================

resource "vault_policy" "k8s_developer_cert" {
  name = "k8s-developer-cert"

  policy = <<EOT

# K8s developer can issue developer and viewer certs
path "fzymgc-house/v1/ica1/v1/issue/k8s-developer" {
  capabilities = ["create", "update"]
}
path "fzymgc-house/v1/ica1/v1/issue/k8s-viewer" {
  capabilities = ["create", "update"]
}

# Read CA chain for kubeconfig
path "fzymgc-house/v1/ica1/v1/ca_chain" {
  capabilities = ["read"]
}

EOT
}

# =============================================================================
# Viewer Policy - Can only issue viewer certs
# =============================================================================

resource "vault_policy" "k8s_viewer_cert" {
  name = "k8s-viewer-cert"

  policy = <<EOT

# K8s viewer can only issue viewer certs
path "fzymgc-house/v1/ica1/v1/issue/k8s-viewer" {
  capabilities = ["create", "update"]
}

# Read CA chain for kubeconfig
path "fzymgc-house/v1/ica1/v1/ca_chain" {
  capabilities = ["read"]
}

EOT
}
