resource "grafana_contact_point" "discord" {
  name = "Discord"

  discord {
    url = data.vault_kv_secret_v2.grafana.data["discord_webhook_url"]
  }
}

resource "grafana_notification_policy" "default" {
  contact_point   = grafana_contact_point.discord.name
  group_by        = ["alertname", "severity"]
  group_wait      = "30s"
  group_interval  = "5m"
  repeat_interval = "3h"
}
