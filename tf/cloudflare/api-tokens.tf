# SPDX-License-Identifier: MIT
# terraform: language=hcl
# api-tokens.tf - Cloudflare API token configuration
#
# NOTE: Cloudflare provider v5 has breaking changes for cloudflare_api_token
# that make Terraform-managed token creation unreliable. See:
# https://github.com/cloudflare/terraform-provider-cloudflare/issues/5062
#
# Current approach: Manually create bootstrap token with full permissions.
# Future: When v5 stabilizes, add workload token creation here.

# =============================================================================
# Bootstrap Token Documentation
# =============================================================================
#
# The bootstrap token is manually created in Cloudflare Dashboard and stored
# in Vault at: secret/fzymgc-house/infrastructure/cloudflare/bootstrap-token
#
# Required permissions for the bootstrap token:
#
# Account-level:
#   - Account Settings: Read
#   - Workers Scripts: Edit
#   - Cloudflare Tunnel: Edit
#   - (Optional) API Tokens: Edit (for future workload token creation)
#
# Zone-level:
#   - DNS: Edit
#   - Zone: Read
#
# See docs/cloudflare.md for setup instructions.
# =============================================================================
