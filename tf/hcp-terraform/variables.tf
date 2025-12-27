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

variable "notification_worker_url" {
  description = "Cloudflare Worker URL for HCP TF notifications (hcp-terraform-discord)"
  type        = string
  sensitive   = true
}

variable "notification_hmac_token" {
  description = "HMAC token for notification signature verification"
  type        = string
  sensitive   = true
  default     = ""  # Optional - when empty, notifications sent without HMAC
}
