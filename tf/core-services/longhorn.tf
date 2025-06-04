resource "helm_release" "longhorn" {
  name = "longhorn"
  chart = "longhorn"
  namespace = "longhorn-system"
  create_namespace = true
  repository = "https://charts.longhorn.io"
  version = "1.9.0"
  values = [
    file("${path.module}/helm-values/longhorn.yaml")
  ]
}

resource "kubernetes_storage_class" "longhorn-single-replica" {
  metadata {
    name = "longhorn-single-replica"
  }
  storage_provisioner = "longhorn.io/longhorn"
  allow_volume_expansion = true
  reclaim_policy = "Delete"
  volume_binding_mode = "Immediate"
  parameters = {
    "numberOfReplicas" = "1"
  }
}