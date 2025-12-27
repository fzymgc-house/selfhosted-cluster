# All sensitive credentials are read from Vault
# See vault.tf for data sources

variable "vault_addr" {
  description = "Vault server address"
  type        = string
  default     = "https://vault.fzymgc.house"
}

variable "grafana_url" {
  description = "Grafana server URL"
  type        = string
  default     = "https://grafana.fzymgc.house"
}

variable "tfc_workload_identity_token_path" {
  description = "Path to HCP TF workload identity JWT (empty for local dev)"
  type        = string
  default     = ""
}
