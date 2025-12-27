// notifications.tf - Discord notification configuration via Cloudflare Worker
//
// Notifications are sent to the hcp-terraform-discord Cloudflare Worker,
// which transforms them into Discord embeds and forwards to the webhook.
// HMAC signature validation ensures requests are authentic.
//
// Secrets are read from Vault (populated by tf/cloudflare and tf/vault modules):
// - Worker URL: secret/fzymgc-house/infrastructure/cloudflare/hcp-terraform-worker
// - HMAC token: secret/fzymgc-house/infrastructure/cloudflare/hcp-terraform-hmac

# Worker URL for HCP Terraform notifications (created by tf/cloudflare)
data "vault_kv_secret_v2" "hcp_terraform_worker" {
  mount = "secret"
  name  = "fzymgc-house/infrastructure/cloudflare/hcp-terraform-worker"
}

# HMAC token for notification signature verification (created by tf/vault)
data "vault_kv_secret_v2" "hcp_terraform_hmac" {
  mount = "secret"
  name  = "fzymgc-house/infrastructure/cloudflare/hcp-terraform-hmac"
}

resource "tfe_notification_configuration" "discord" {
  for_each = tfe_workspace.this

  workspace_id     = each.value.id
  name             = "discord"
  enabled          = true
  destination_type = "generic"
  url              = data.vault_kv_secret_v2.hcp_terraform_worker.data["url"]

  # HMAC token for signature verification (X-TFE-Notification-Signature header)
  # Worker validates X-TFE-Notification-Signature header using HMAC-SHA512
  token = data.vault_kv_secret_v2.hcp_terraform_hmac.data["token"]

  triggers = [
    "run:planning",
    "run:applying",
    "run:completed",
    "run:errored",
  ]
}
