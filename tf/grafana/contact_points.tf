resource "grafana_contact_point" "discord" {
  name = "Discord"

  webhook {
    url = var.discord_webhook_url
  }
}

resource "grafana_notification_policy" "default" {
  contact_point   = grafana_contact_point.discord.name
  group_by        = ["alertname", "severity"]
  group_wait      = "30s"
  group_interval  = "5m"
  repeat_interval = "3h"
}
