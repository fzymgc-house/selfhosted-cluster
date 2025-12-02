// variables.tf - Input variables for Teleport module

variable "teleport_identity_file" {
  description = "Path to Teleport identity file for provider authentication"
  type        = string
  sensitive   = true
}

variable "authentik_issuer_url" {
  description = "Authentik OIDC issuer URL"
  type        = string
  default     = "https://auth.fzymgc.house/application/o/teleport/"
}

variable "teleport_public_addr" {
  description = "Public address of Teleport cluster"
  type        = string
  default     = "teleport.fzymgc.house"
}
