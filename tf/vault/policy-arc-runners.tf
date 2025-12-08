# -*- coding: utf-8; mode: terraform -*-
# SPDX-License-Identifier: MIT

# Policy for ARC runners to read GitHub token secret
resource "vault_policy" "arc_runners" {
  name = "arc-runners"

  policy = <<-EOT
    # Read access to GitHub token for Actions runners
    path "secret/data/fzymgc-house/cluster/github" {
      capabilities = ["read"]
    }

    # List capability for the github path
    path "secret/metadata/fzymgc-house/cluster/github" {
      capabilities = ["list"]
    }
  EOT
}
