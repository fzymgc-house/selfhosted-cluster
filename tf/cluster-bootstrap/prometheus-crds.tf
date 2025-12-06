// prometheus-crds.tf - Prometheus Operator CRDs installation

resource "kubernetes_namespace" "prometheus" {
  metadata {
    name = "prometheus"
  }
}

resource "helm_release" "prometheus_operator_crds" {
  name       = "prometheus-operator-crds"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-operator-crds"
  version    = var.prometheus_operator_crds_version
  namespace  = kubernetes_namespace.prometheus.metadata[0].name

  wait = true
}
