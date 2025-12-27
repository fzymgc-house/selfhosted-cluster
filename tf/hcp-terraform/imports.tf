// imports.tf - Import existing HCP Terraform workspaces into state
//
// These workspaces already exist in HCP Terraform. The import blocks
// tell Terraform to import them rather than try to create new ones.
// After successful import, this file can be removed.

import {
  to = tfe_workspace.this["main-cluster-vault"]
  id = "fzymgc-house/main-cluster-vault"
}

import {
  to = tfe_workspace.this["main-cluster-authentik"]
  id = "fzymgc-house/main-cluster-authentik"
}

import {
  to = tfe_workspace.this["main-cluster-grafana"]
  id = "fzymgc-house/main-cluster-grafana"
}

import {
  to = tfe_workspace.this["main-cluster-cloudflare"]
  id = "fzymgc-house/main-cluster-cloudflare"
}

import {
  to = tfe_workspace.this["main-cluster-core-services"]
  id = "fzymgc-house/main-cluster-core-services"
}

import {
  to = tfe_workspace.this["main-cluster-bootstrap"]
  id = "fzymgc-house/main-cluster-bootstrap"
}
