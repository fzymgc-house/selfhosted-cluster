// imports.tf - Import blocks for existing workspaces

import {
  to = tfe_workspace.this["vault"]
  id = "fzymgc-house/vault"
}

import {
  to = tfe_workspace.this["authentik"]
  id = "fzymgc-house/authentik"
}

import {
  to = tfe_workspace.this["cloudflare"]
  id = "fzymgc-house/cloudflare"
}

import {
  to = tfe_workspace.this["cluster-bootstrap"]
  id = "fzymgc-house/cluster-bootstrap"
}
