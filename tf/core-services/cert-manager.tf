resource "helm_release" "cert-manager" {
  name             = "cert-manager"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  version          = "v1.17.2"
  values = [
    file("${path.module}/helm-values/cert-manager.yaml")
  ]
}

data "onepassword_item" "fzymgc-house-ica1" {
  title = "fzymgc-ica1-ca"
  vault = "fzymgc-house"
}

data "onepassword_item" "fzymgc-house-root-ca" {
  title = "fzymgc-root-ca"
  vault = "fzymgc-house"
}

resource "kubernetes_secret" "fzymgc-house-ica1" {
  metadata {
    name = "fzymgc-house-ica1"
    namespace = helm_release.cert-manager.namespace
  }
  type = "kubernetes.io/tls"
  data = {
    "tls.crt" = data.onepassword_item.fzymgc-house-ica1.section[0].field[2].value
    "tls.key" = data.onepassword_item.fzymgc-house-ica1.section[0].field[3].value
  }
}

resource "kubernetes_manifest" "fzymgc-house-ica1-issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind = "Issuer"
    metadata = {
      name = "fzymgc-house-ica1"
      namespace = helm_release.cert-manager.namespace
    }
    spec = {
      ca = {
        secretName = kubernetes_secret.fzymgc-house-ica1.metadata[0].name
      }
    }
  }
}