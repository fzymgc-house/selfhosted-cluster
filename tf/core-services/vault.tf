
resource "kubernetes_namespace" "vault" {
  metadata {
    name = "vault"
  }
}

resource "kubernetes_secret" "vault-fzymgc-house-ica1" {
  metadata {
    name = "fzymgc-house-ica1"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }
  type = "kubernetes.io/tls"
  data = {
    "tls.crt" = data.onepassword_item.fzymgc-house-ica1.section[0].field[2].value
    "tls.key" = data.onepassword_item.fzymgc-house-ica1.section[0].field[3].value
  }
}

resource "kubernetes_manifest" "vault-fzymgc-house-ica1-issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind = "Issuer"
    metadata = {
      name = "fzymgc-house-ica1"
      namespace = kubernetes_namespace.vault.metadata[0].name
    }
    spec = {
      ca = {
        secretName = kubernetes_secret.fzymgc-house-ica1.metadata[0].name
      }
    }
  }
}

resource "kubernetes_manifest" "vault-ha-tls" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "vault-ha-tls"
      namespace = kubernetes_namespace.vault.metadata[0].name
    }
    spec = {
      secretName = "vault-ha-tls"

      usages = [
        "server auth",
        "client auth",
      ]

      issuerRef = {
        name = "fzymgc-house-ica1"
        kind = "Issuer"
      }
      commonName = "*.vault.svc.cluster.local"
      dnsNames = [
        "*.vault.svc.cluster.local",
        "*.vault-internal",
        "*.vault",
        "127.0.0.1",
        "vault.fzymgc.house",
      ]
      privateKey = {
        algorithm = "ECDSA"
        size      = 384
      }
    }
  }
}


# resource "helm_release" "vault" {
#   name = "vault"
#   chart = "vault"
#   namespace = "vault"
#   create_namespace = true
#   repository = "https://helm.releases.hashicorp.com"
#   version = "0.30.0"
#   values = [
#     file("${path.module}/helm-values/vault.yaml")
#   ]
# }