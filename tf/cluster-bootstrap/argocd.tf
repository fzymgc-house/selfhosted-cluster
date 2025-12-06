// argocd.tf - ArgoCD installation and configuration

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

# Get ArgoCD secrets from Vault
data "vault_kv_secret_v2" "argocd_config" {
  mount = "secret"
  name  = "fzymgc-house/cluster/argocd"
}

data "vault_kv_secret_v2" "fzymgc_ica1_ca_fullchain" {
  mount = "secret"
  name  = "fzymgc-house/infrastructure/pki/fzymgc-ica1-ca"
}

# OIDC configuration secret for Authentik
resource "kubernetes_secret" "argocd_oidc_secret" {
  metadata {
    name      = "argocd-oidc-secret"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "app.kubernetes.io/part-of" = "argocd"
    }
  }

  type = "Opaque"

  data = {
    "authentik.client_id"     = data.vault_kv_secret_v2.argocd_config.data["authentik_client_id"]
    "authentik.client_secret" = data.vault_kv_secret_v2.argocd_config.data["authentik_client_secret"]
  }

  depends_on = [helm_release.external_secrets_operator]
}

# Repository secret for GitHub App authentication
resource "kubernetes_secret" "argocd_selfhosted_repo" {
  metadata {
    name      = "argocd-selfhosted-repo"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  type = "Opaque"

  data = {
    name                     = "selfhosted-cluster"
    project                  = "default"
    type                     = "git"
    url                      = "https://github.com/fzymgc-house/selfhosted-cluster"
    githubAppID              = "1759545"
    githubAppInstallationID  = "80236294"
    githubAppPrivateKey      = base64decode(data.vault_kv_secret_v2.argocd_config.data["github_app_private_key"])
  }

  depends_on = [helm_release.external_secrets_operator]
}

# ArgoCD secret managed via External Secrets
resource "kubernetes_manifest" "argocd_secret_external" {
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "argocd-secret"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      secretStoreRef = {
        name = "vault"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "argocd-secret"
        creationPolicy = "Owner"
        deletionPolicy = "Delete"
        template = {
          type = "Opaque"
          data = {
            "admin.password"        = "{{ .admin_password | b64enc}}"
            "admin.passwordMtime"   = "{{ .admin_password_mtime | b64enc}}"
            "server.secretkey"      = "{{ .server_secret_key | b64enc}}"
            "webhook.github.secret" = "{{ .webhook_github_secret | b64enc }}"
          }
        }
      }
      data = [
        {
          secretKey = "admin_password"
          remoteRef = {
            key      = "fzymgc-house/cluster/argocd"
            property = "admin.password"
          }
        },
        {
          secretKey = "admin_password_mtime"
          remoteRef = {
            key      = "fzymgc-house/cluster/argocd"
            property = "admin.password_mtime"
          }
        },
        {
          secretKey = "server_secret_key"
          remoteRef = {
            key      = "fzymgc-house/cluster/argocd"
            property = "server.secretkey"
          }
        },
        {
          secretKey = "webhook_github_secret"
          remoteRef = {
            key      = "fzymgc-house/cluster/argocd"
            property = "webhook.github.secret"
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.vault_cluster_secret_store]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  wait = false

  values = [yamlencode({
    global = {
      addPrometheusAnnotations = true
      domain                   = "argocd.${var.cluster_domain}"
    }
    configs = {
      cm = {
        url = "https://argocd.${var.cluster_domain}"
        "dex.config" = <<-EOT
          connectors:
            - type: oidc
              id: oidc
              name: oidc
              config:
                issuer: https://auth.${var.cluster_domain}/application/o/argo-cd/
                clientID: $argocd-oidc-secret:authentik.client_id
                clientSecret: $argocd-oidc-secret:authentik.client_secret
                rootCAs:
                  - ${base64encode(data.vault_kv_secret_v2.fzymgc_ica1_ca_fullchain.data["fullchain"])}
                insecureEnableGroups: true
                scopes:
                  - email
                  - openid
                  - profile
                  - groups
                getUserInfo: true
                claimMapping:
                  groups: groups
        EOT
      }
      params = {
        "server.insecure" = true
      }
      rbac = {
        "policy.csv" = <<-EOT
          g, argocd-admin, role:admin
          g, argocd-user, role:readonly
        EOT
      }
      secret = {
        create = false
      }
    }
    certificate = {
      enabled = true
    }
    dex = {
      metrics = {
        enabled = true
        serviceMonitor = {
          enabled = true
        }
      }
    }
    redis-ha = {
      exporter = {
        enabled = true
        serviceMonitor = {
          enabled = true
        }
      }
    }
    controller = {
      replicas = 1
      metrics = {
        enabled = true
        serviceMonitor = {
          enabled = true
        }
      }
    }
    server = {
      replicas = 2
      metrics = {
        enabled = true
        serviceMonitor = {
          enabled = true
        }
      }
      ingress = {
        enabled = true
        annotations = {
          "cert-manager.io/cluster-issuer" = "fzymgc-house-issuer"
        }
        extraTls = [{
          hosts      = ["argocd.${var.cluster_domain}"]
          secretName = "argocd-tls"
        }]
      }
    }
    repoServer = {
      replicas = 2
      metrics = {
        enabled = true
        serviceMonitor = {
          enabled = true
        }
      }
    }
    applicationSet = {
      replicas = 2
      metrics = {
        enabled = true
        serviceMonitor = {
          enabled = true
        }
      }
    }
  })]

  depends_on = [
    kubernetes_secret.argocd_oidc_secret,
    kubernetes_secret.argocd_selfhosted_repo,
    kubernetes_manifest.argocd_secret_external,
    helm_release.prometheus_operator_crds,
    helm_release.cert_manager,
    helm_release.metallb
  ]
}

# App of Apps Application
resource "kubernetes_manifest" "cluster_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "cluster-app"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/fzymgc-house/selfhosted-cluster"
        targetRevision = "HEAD"
        path           = "argocd/cluster-app"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "ServerSideApply=true"
        ]
      }
    }
  }

  depends_on = [helm_release.argocd]
}
