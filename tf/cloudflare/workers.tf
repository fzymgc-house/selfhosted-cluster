# SPDX-License-Identifier: MIT
# terraform: language=hcl
# workers.tf - Cloudflare Workers managed via Terraform
#
# This deploys Workers with their code and secrets in a single apply.
# Worker code lives in cloudflare/workers/<name>/.

# =============================================================================
# Vault Data Sources for Worker Secrets
# =============================================================================

# Discord webhook URL for HCP Terraform notifications
data "vault_kv_secret_v2" "discord_webhook" {
  mount = "secret"
  name  = "fzymgc-house/infrastructure/cloudflare/discord-webhook"
}

# =============================================================================
# HCP Terraform Discord Notification Worker
# =============================================================================

# The Worker resource defines persistent settings (name, tags)
resource "cloudflare_worker" "hcp_terraform_discord" {
  account_id = var.cloudflare_account_id
  name       = "hcp-terraform-discord"
  tags       = ["terraform", "notifications", "discord"]
}

# The Worker version deploys code + bindings
resource "cloudflare_worker_version" "hcp_terraform_discord" {
  account_id         = var.cloudflare_account_id
  worker_id          = cloudflare_worker.hcp_terraform_discord.id
  compatibility_date = "2024-09-23"
  main_module        = "worker.js"

  modules = [{
    name         = "worker.js"
    content_type = "application/javascript+module"
    content_file = "${path.module}/../../cloudflare/workers/hcp-terraform-discord/worker.js"
  }]

  bindings = [
    {
      type = "secret_text"
      name = "DISCORD_WEBHOOK_URL"
      text = data.vault_kv_secret_v2.discord_webhook.data["url"]
    }
  ]
}

# Deploy the version to production
resource "cloudflare_workers_deployment" "hcp_terraform_discord" {
  account_id  = var.cloudflare_account_id
  script_name = cloudflare_worker.hcp_terraform_discord.name
  strategy    = "percentage"

  versions = [
    {
      version_id = cloudflare_worker_version.hcp_terraform_discord.id
      percentage = 100
    }
  ]
}
