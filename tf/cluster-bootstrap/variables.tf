// variables.tf - Input variables for cluster bootstrap

variable "cluster_domain" {
  description = "Base domain for the cluster"
  type        = string
  default     = "fzymgc.house"
}

variable "argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "9.1.6"
}

variable "cert_manager_version" {
  description = "cert-manager Helm chart version"
  type        = string
  default     = "v1.19.1"
}

variable "external_secrets_version" {
  description = "External Secrets Operator Helm chart version"
  type        = string
  default     = "1.1.1"
}

variable "longhorn_version" {
  description = "Longhorn Helm chart version"
  type        = string
  default     = "1.10.1"
}

variable "metallb_version" {
  description = "MetalLB Helm chart version"
  type        = string
  default     = "0.15.3"
}

variable "prometheus_operator_crds_version" {
  description = "Prometheus Operator CRDs Helm chart version"
  type        = string
  default     = "25.0.0"
}
