// notifications.tf - Discord notification configuration via Cloudflare Worker
//
// Notifications are sent to the hcp-terraform-discord Cloudflare Worker,
// which transforms them into Discord embeds and forwards to the webhook.
// HMAC signature validation is optional but recommended.

resource "tfe_notification_configuration" "discord" {
  for_each = tfe_workspace.this

  workspace_id     = each.value.id
  name             = "discord"
  enabled          = true
  destination_type = "generic"
  url              = var.notification_worker_url

  # HMAC token for signature verification (X-TFE-Notification-Signature header)
  # When set, the Worker validates signatures before processing
  token = var.notification_hmac_token != "" ? var.notification_hmac_token : null

  triggers = [
    "run:planning",
    "run:applying",
    "run:completed",
    "run:errored",
  ]
}
