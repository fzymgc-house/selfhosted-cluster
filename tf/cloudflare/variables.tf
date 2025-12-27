# SPDX-License-Identifier: MIT
# terraform: language=hcl

variable "vault_addr" {
  description = "Vault server address"
  type        = string
  default     = "https://vault.fzymgc.house"
}

variable "tfc_vault_dynamic_credentials" {
  description = "HCP TF dynamic credentials for Vault (injected when TFC_VAULT_PROVIDER_AUTH=true)"
  type = object({
    default = object({
      token_filename = string
      address        = string
      namespace      = string
      ca_cert_file   = string
    })
    aliases = map(object({
      token_filename = string
      address        = string
      namespace      = string
      ca_cert_file   = string
    }))
  })
  default = null

  validation {
    condition = (
      var.tfc_vault_dynamic_credentials == null ||
      try(var.tfc_vault_dynamic_credentials.default.token_filename, "") != ""
    )
    error_message = "tfc_vault_dynamic_credentials.default.token_filename is required when dynamic credentials are provided."
  }
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID for tunnel creation"
  type        = string
  default     = "40753dbbbbd1540f02bd0707935ddb3f"
  sensitive   = true

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

variable "webhook_domain" {
  description = "Domain for webhook endpoints (using fzymgc.net to avoid split-horizon DNS)"
  type        = string
  default     = "fzymgc.net"
}

variable "webhook_suffix" {
  description = "Suffix appended to service name for webhook hostnames (e.g., -wh gives windmill-wh.fzymgc.net)"
  type        = string
  default     = "-wh"
}

variable "webhook_services" {
  description = "Map of webhook services with their subdomain and upstream configuration"
  type = map(object({
    service_url = string
  }))
  default = {
    windmill = {
      service_url = "http://windmill-app.windmill.svc.cluster.local:8000"
    }
  }

  validation {
    condition     = alltrue([for k, v in var.webhook_services : can(regex("^https?://", v.service_url))])
    error_message = "All service URLs must start with http:// or https://. Invalid URLs will cause origin_server_name parsing failures."
  }
}
