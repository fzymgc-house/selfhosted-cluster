// variables.tf - Input variables for core-services module

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
