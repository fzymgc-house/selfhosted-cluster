// variables.tf - Input variables for authentik module

variable "vault_addr" {
  description = "Vault server address"
  type        = string
  default     = "https://vault.fzymgc.house"
}

variable "tfc_workload_identity_token_path" {
  description = "Path to HCP TF workload identity JWT (empty for local dev)"
  type        = string
  default     = ""
}
