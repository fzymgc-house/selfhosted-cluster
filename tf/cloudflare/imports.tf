# SPDX-License-Identifier: MIT
# terraform: language=hcl
# imports.tf - Import blocks for existing Cloudflare resources
#
# These import blocks adopt existing resources into Terraform state.
# Remove after successful import (imports are one-time operations).

# Import existing hcp-terraform-discord Worker
# Created via wrangler before Terraform management
import {
  to = cloudflare_worker.hcp_terraform_discord
  id = "40753dbbbbd1540f02bd0707935ddb3f/hcp-terraform-discord"
}
