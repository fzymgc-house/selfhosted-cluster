# workers.tf - Cloudflare Workers secret management
#
# Workers are deployed via wrangler (see cloudflare/workers/), but secrets
# are managed here for GitOps consistency and Vault integration.

# Discord webhook URL for HCP Terraform notifications
data "vault_kv_secret_v2" "discord_webhook" {
  mount = "secret"
  name  = "fzymgc-house/infrastructure/cloudflare/discord-webhook"
}

# Set the Discord webhook secret on the HCP Terraform notification Worker
resource "cloudflare_workers_secret" "hcp_terraform_discord_webhook" {
  account_id  = var.cloudflare_account_id
  script_name = "hcp-terraform-discord"
  secret_name = "DISCORD_WEBHOOK_URL"
  secret_text = data.vault_kv_secret_v2.discord_webhook.data["url"]
}
