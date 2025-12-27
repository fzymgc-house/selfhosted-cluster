# variables.tf - Input variables

variable "organization" {
  description = "HCP Terraform organization name"
  type        = string
  default     = "fzymgc-house"
}

variable "organization_email" {
  description = "HCP Terraform organization admin email"
  type        = string
  default     = "terraform-admin@sean.fzymgc.email"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.organization_email))
    error_message = "Must be a valid email address."
  }
}

variable "github_repo" {
  description = "GitHub repository identifier"
  type        = string
  default     = "fzymgc-house/selfhosted-cluster"
}

variable "vault_addr" {
  description = "Vault server address"
  type        = string
  default     = "https://vault.fzymgc.house"
}
