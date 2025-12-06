// cert-manager.tf - cert-manager installation and configuration

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

# Get CA certificate and key from Vault
data "vault_kv_secret_v2" "fzymgc_ica1_ca" {
  mount = "fzymgc-house"
  name  = "infrastructure/pki/fzymgc-ica1-ca"
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io/"
  chart      = "cert-manager"
  version    = var.cert_manager_version
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name

  wait = true

  values = [yamlencode({
    crds = {
      enabled = true
    }
    replicaCount = 2
    dns01RecursiveNameservers      = "https://1.1.1.1/dns-query"
    dns01RecursiveNameserversOnly  = true
    podDisruptionBudget = {
      enabled = true
    }
    prometheus = {
      servicemonitor = {
        enabled = true
      }
    }
    webhook = {
      replicaCount = 2
      podDisruptionBudget = {
        enabled = true
      }
    }
    cainjector = {
      replicaCount = 2
      podDisruptionBudget = {
        enabled = true
      }
    }
    config = {
      apiVersion = "controller.config.cert-manager.io/v1alpha1"
      kind       = "ControllerConfiguration"
      logging = {
        verbosity = 2
        format    = "text"
      }
      enableGatewayAPI = true
      featureGates = {
        ServerSideApply                       = true
        UseCertificateRequestBasicConstraints = true
        OtherNames                            = true
      }
    }
  })]

  depends_on = [helm_release.prometheus_operator_crds]
}

resource "kubernetes_secret" "fzymgc_house_ica1_key" {
  metadata {
    name      = "fzymgc-house-ica1-key"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }

  type = "Opaque"

  data = {
    "tls.crt" = data.vault_kv_secret_v2.fzymgc_ica1_ca.data["cert"]
    "tls.key" = data.vault_kv_secret_v2.fzymgc_ica1_ca.data["cleartext_key"]
  }

  depends_on = [helm_release.cert_manager]
}

resource "kubernetes_manifest" "fzymgc_house_issuer" {
  manifest = yamldecode(file("${path.module}/manifests/fzymgc-house-issuer.yaml"))

  depends_on = [kubernetes_secret.fzymgc_house_ica1_key]
}
