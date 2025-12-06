// metallb.tf - MetalLB load balancer installation and configuration

resource "kubernetes_namespace" "metallb" {
  metadata {
    name = "metallb"
  }
}

resource "helm_release" "metallb" {
  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  version    = var.metallb_version
  namespace  = kubernetes_namespace.metallb.metadata[0].name

  wait = true

  depends_on = [helm_release.longhorn]
}

resource "kubernetes_manifest" "metallb_ip_address_pool" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "default"
      namespace = kubernetes_namespace.metallb.metadata[0].name
    }
    spec = {
      addresses = [
        "192.168.20.145-192.168.20.149",
        "192.168.20.155-192.168.20.159"
      ]
    }
  }

  depends_on = [helm_release.metallb]
}

resource "kubernetes_manifest" "metallb_l2_advertisement" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = "default"
      namespace = kubernetes_namespace.metallb.metadata[0].name
    }
    spec = {
      ipAddressPools = ["default"]
    }
  }

  depends_on = [kubernetes_manifest.metallb_ip_address_pool]
}
