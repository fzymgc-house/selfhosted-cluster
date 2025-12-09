# SPDX-License-Identifier: MIT
# terraform: language=hcl

variable "cloudflare_account_id" {
  description = "Cloudflare account ID for tunnel creation"
  type        = string
  default     = "40753dbbbbd1540f02bd0707935ddb3f"

  validation {
    condition     = var.cloudflare_account_id != "your-account-id-here"
    error_message = "Cloudflare account ID must be set to your actual account ID. Find it in Cloudflare dashboard > Overview."
  }
}

variable "tunnel_name" {
  description = "Name of the Cloudflare Tunnel"
  type        = string
  default     = "fzymgc-house-main"
}

variable "webhook_base_domain" {
  description = "Base domain for webhook subdomains"
  type        = string
  default     = "wh.fzymgc.house"
}

variable "webhook_services" {
  description = "Map of webhook services with their subdomain and upstream configuration"
  type = map(object({
    service_url = string
  }))
  default = {
    windmill = {
      service_url = "http://windmill.windmill.svc.cluster.local:8000"
    }
  }
}
