# SPDX-License-Identifier: MIT

resource "vault_policy" "github_actions" {
  name = "github-actions"

  policy = <<-EOT
    # Read windmill secrets for sync script
    path "secret/data/fzymgc-house/cluster/windmill" {
      capabilities = ["read"]
    }

    # Read GitHub secrets
    path "secret/data/fzymgc-house/cluster/github" {
      capabilities = ["read"]
    }
  EOT
}
