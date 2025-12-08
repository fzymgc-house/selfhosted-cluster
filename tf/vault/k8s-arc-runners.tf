# -*- coding: utf-8; mode: terraform -*-
# SPDX-License-Identifier: MIT

# Kubernetes auth role for ARC runners service account
resource "vault_kubernetes_auth_backend_role" "arc_runners" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "arc-runners"
  bound_service_account_namespaces = ["arc-runners"]
  bound_service_account_names      = ["arc-runner-external-secrets"]
  audience                         = "https://kubernetes.default.svc.cluster.local"
  token_policies                   = ["default", "arc-runners"]
}
