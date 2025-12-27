// variables.tf - Input variables for vault module

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

variable "kubeconfig_path" {
  description = "Path to kubeconfig file (empty for in-cluster auth in HCP TF agent)"
  type        = string
  default     = "~/.kube/configs/fzymgc-house-admin.yml"
}

variable "kubeconfig_context" {
  description = "Kubeconfig context to use (empty for in-cluster auth)"
  type        = string
  default     = "fzymgc-house"
}
