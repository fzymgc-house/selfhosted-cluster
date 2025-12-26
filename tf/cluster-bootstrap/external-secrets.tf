// external-secrets.tf - External Secrets Operator installation and configuration

resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets"
  }
}

resource "helm_release" "external_secrets_operator" {
  name       = "external-secrets-operator"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.external_secrets_version
  namespace  = kubernetes_namespace.external_secrets.metadata[0].name

  wait = true

  values = [yamlencode({
    installCRDs = true
  })]

  depends_on = [helm_release.cert_manager]
}

# Get Vault CA chain from Vault
data "vault_kv_secret_v2" "vault_ca_chain" {
  mount = "secret"
  name  = "fzymgc-house/infrastructure/pki/fzymgc-ica1-ca"
}

resource "kubernetes_secret" "vault_ca_chain" {
  metadata {
    name      = "vault-ca-chain"
    namespace = kubernetes_namespace.external_secrets.metadata[0].name
  }

  type = "Opaque"

  data = {
    "ca.crt" = data.vault_kv_secret_v2.vault_ca_chain.data["fullchain"]
  }

  depends_on = [helm_release.external_secrets_operator]
}

resource "kubernetes_manifest" "vault_cluster_secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "vault"
    }
    spec = {
      provider = {
        vault = {
          server  = "https://vault-internal.vault:8200"
          path    = "secret"
          version = "v2"
          auth = {
            kubernetes = {
              mountPath = "kubernetes"
              role      = "external-secrets"
            }
          }
          caProvider = {
            type      = "Secret"
            name      = kubernetes_secret.vault_ca_chain.metadata[0].name
            key       = "ca.crt"
            namespace = kubernetes_secret.vault_ca_chain.metadata[0].namespace
          }
        }
      }
    }
  }

  depends_on = [kubernetes_secret.vault_ca_chain]
}
