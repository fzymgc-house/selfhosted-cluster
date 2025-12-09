# SPDX-License-Identifier: MIT
# terraform: language=hcl

variable "cloudflare_account_id" {
  description = "Cloudflare account ID for tunnel creation"
  type        = string
  default     = "your-account-id-here" # TODO: Replace with actual account ID from Cloudflare dashboard
}

variable "tunnel_name" {
  description = "Name of the Cloudflare Tunnel"
  type        = string
  default     = "fzymgc-house-main"
}

variable "webhook_hostname" {
  description = "Hostname for webhook endpoints"
  type        = string
  default     = "wh.fzymgc.house"
}
