variable "grafana_url" {
  description = "URL of the Grafana instance"
  type        = string
}

variable "grafana_api_key" {
  description = "Grafana API key"
  type        = string
  sensitive   = true
}

variable "discord_webhook_url" {
  description = "Discord webhook URL for notifications"
  type        = string
  sensitive   = true
}


