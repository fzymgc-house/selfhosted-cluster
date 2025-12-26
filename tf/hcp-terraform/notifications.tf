// notifications.tf - Discord notification configuration via Cloudflare Worker

resource "tfe_notification_configuration" "discord" {
  for_each = tfe_workspace.this

  workspace_id     = each.value.id
  name             = "discord"
  enabled          = true
  destination_type = "generic"
  url              = var.discord_webhook_url

  triggers = [
    "run:planning",
    "run:applying",
    "run:completed",
    "run:errored",
  ]
}
