// outputs.tf - Output values from cluster bootstrap

output "argocd_namespace" {
  description = "ArgoCD namespace"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "longhorn_namespace" {
  description = "Longhorn namespace"
  value       = kubernetes_namespace.longhorn_system.metadata[0].name
}

output "cert_manager_namespace" {
  description = "cert-manager namespace"
  value       = kubernetes_namespace.cert_manager.metadata[0].name
}

output "external_secrets_namespace" {
  description = "External Secrets namespace"
  value       = kubernetes_namespace.external_secrets.metadata[0].name
}

output "metallb_namespace" {
  description = "MetalLB namespace"
  value       = kubernetes_namespace.metallb_system.metadata[0].name
}
