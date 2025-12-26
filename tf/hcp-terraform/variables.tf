// variables.tf - Input variables

variable "organization" {
  description = "HCP Terraform organization name"
  type        = string
  default     = "fzymgc-house"
}

variable "github_repo" {
  description = "GitHub repository identifier"
  type        = string
  default     = "fzymgc-house/selfhosted-cluster"
}

variable "discord_webhook_url" {
  description = "Cloudflare Worker URL for Discord notifications"
  type        = string
  sensitive   = true
}
