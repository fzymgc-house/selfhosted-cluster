// longhorn.tf - Longhorn distributed storage installation and configuration

resource "kubernetes_namespace" "longhorn_system" {
  metadata {
    name = "longhorn-system"
  }
}

# Get Longhorn secrets from Vault
data "vault_kv_secret_v2" "longhorn_crypto_key" {
  mount = "secret"
  name  = "fzymgc-house/cluster/longhorn/crypto-key"
}

data "vault_kv_secret_v2" "longhorn_cloudflare_r2" {
  mount = "secret"
  name  = "fzymgc-house/cluster/longhorn/cloudflare-r2"
}

resource "helm_release" "longhorn" {
  name       = "longhorn"
  repository = "https://charts.longhorn.io/"
  chart      = "longhorn"
  version    = var.longhorn_version
  namespace  = kubernetes_namespace.longhorn_system.metadata[0].name

  values = [yamlencode({
    persistence = {
      defaultClassReplicaCount = 2
      defaultDataLocality      = "best-effort"
      volumeBindingMode        = "WaitForFirstConsumer"
    }
    defaultSettings = {
      defaultDataPath     = "/data/longhorn"
      snapshotMaxCount    = "10"
      defaultReplicaCount = "2"
    }
    defaultBackupStore = {
      backupTarget                 = "s3://fzymgc-cluster-storage@us-east-1/longhorn-backups"
      backupTargetCredentialSecret = "longhorn-backup-creds"
    }
  })]

  depends_on = [helm_release.external_secrets_operator]
}

resource "kubernetes_secret" "longhorn_crypto_config" {
  metadata {
    name      = "longhorn-crypto-config"
    namespace = kubernetes_namespace.longhorn_system.metadata[0].name
  }

  data = {
    CRYPTO_KEY_VALUE    = data.vault_kv_secret_v2.longhorn_crypto_key.data["password"]
    CRYPTO_KEY_PROVIDER = "secret"
    CRYPTO_KEY_CIPHER   = "aes-xts-plain64"
    CRYPTO_KEY_HASH     = "sha256"
    CRYPTO_KEY_SIZE     = "256"
    CRYPTO_PBKDF        = "argon2i"
  }

  depends_on = [helm_release.longhorn]
}

resource "kubernetes_secret" "longhorn_backup_creds" {
  metadata {
    name      = "longhorn-backup-creds"
    namespace = kubernetes_namespace.longhorn_system.metadata[0].name
  }

  data = {
    AWS_ACCESS_KEY_ID     = data.vault_kv_secret_v2.longhorn_cloudflare_r2.data["username"]
    AWS_SECRET_ACCESS_KEY = data.vault_kv_secret_v2.longhorn_cloudflare_r2.data["password"]
    AWS_ENDPOINTS         = "https://40753dbbbbd1540f02bd0707935ddb3f.r2.cloudflarestorage.com"
  }

  depends_on = [helm_release.longhorn]
}

resource "kubernetes_storage_class" "longhorn_encrypted" {
  metadata {
    name = "longhorn-encrypted"
  }

  storage_provisioner    = "driver.longhorn.io"
  allow_volume_expansion = true
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    numberOfReplicas                                   = "2"
    encrypted                                          = "true"
    dataLocality                                       = "best-effort"
    dataEngine                                         = "v1"
    "csi.storage.k8s.io/provisioner-secret-name"       = kubernetes_secret.longhorn_crypto_config.metadata[0].name
    "csi.storage.k8s.io/provisioner-secret-namespace"  = kubernetes_secret.longhorn_crypto_config.metadata[0].namespace
    "csi.storage.k8s.io/node-publish-secret-name"      = kubernetes_secret.longhorn_crypto_config.metadata[0].name
    "csi.storage.k8s.io/node-publish-secret-namespace" = kubernetes_secret.longhorn_crypto_config.metadata[0].namespace
    "csi.storage.k8s.io/node-stage-secret-name"        = kubernetes_secret.longhorn_crypto_config.metadata[0].name
    "csi.storage.k8s.io/node-stage-secret-namespace"   = kubernetes_secret.longhorn_crypto_config.metadata[0].namespace
    "csi.storage.k8s.io/node-expand-secret-name"       = kubernetes_secret.longhorn_crypto_config.metadata[0].name
    "csi.storage.k8s.io/node-expand-secret-namespace"  = kubernetes_secret.longhorn_crypto_config.metadata[0].namespace
  }

  depends_on = [kubernetes_secret.longhorn_crypto_config]
}

resource "kubernetes_storage_class" "longhorn_1replica_encrypted" {
  metadata {
    name = "longhorn-1replica-encrypted"
  }

  storage_provisioner    = "driver.longhorn.io"
  allow_volume_expansion = true
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    numberOfReplicas                                   = "2"
    encrypted                                          = "true"
    dataLocality                                       = "best-effort"
    dataEngine                                         = "v1"
    "csi.storage.k8s.io/provisioner-secret-name"       = kubernetes_secret.longhorn_crypto_config.metadata[0].name
    "csi.storage.k8s.io/provisioner-secret-namespace"  = kubernetes_secret.longhorn_crypto_config.metadata[0].namespace
    "csi.storage.k8s.io/node-publish-secret-name"      = kubernetes_secret.longhorn_crypto_config.metadata[0].name
    "csi.storage.k8s.io/node-publish-secret-namespace" = kubernetes_secret.longhorn_crypto_config.metadata[0].namespace
    "csi.storage.k8s.io/node-stage-secret-name"        = kubernetes_secret.longhorn_crypto_config.metadata[0].name
    "csi.storage.k8s.io/node-stage-secret-namespace"   = kubernetes_secret.longhorn_crypto_config.metadata[0].namespace
    "csi.storage.k8s.io/node-expand-secret-name"       = kubernetes_secret.longhorn_crypto_config.metadata[0].name
    "csi.storage.k8s.io/node-expand-secret-namespace"  = kubernetes_secret.longhorn_crypto_config.metadata[0].namespace
  }

  depends_on = [kubernetes_secret.longhorn_crypto_config]
}

# Longhorn recurring jobs for automated maintenance
resource "kubernetes_manifest" "longhorn_recurring_job_backup_snapshot_cleanup" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "RecurringJob"
    metadata = {
      name      = "backup-snapshot-cleanup"
      namespace = kubernetes_namespace.longhorn_system.metadata[0].name
    }
    spec = {
      concurrency = 1
      cron        = "5 21 * * *"
      groups      = ["default"]
      labels      = {}
      name        = "backup-snapshot-cleanup"
      parameters  = {}
      retain      = 7
      task        = "snapshot-delete"
    }
  }

  depends_on = [helm_release.longhorn]
}

import {
  to = kubernetes_manifest.longhorn_recurring_job_backup_snapshot_cleanup
  id = "apiVersion=longhorn.io/v1beta2,kind=RecurringJob,namespace=longhorn-system,name=backup-snapshot-cleanup"
}

resource "kubernetes_manifest" "longhorn_recurring_job_daily_backup" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "RecurringJob"
    metadata = {
      name      = "daily-backup"
      namespace = kubernetes_namespace.longhorn_system.metadata[0].name
    }
    spec = {
      concurrency = 4
      cron        = "0 3 * * *"
      groups      = ["default"]
      labels      = {}
      name        = "daily-backup"
      parameters = {
        full-backup-interval = "7"
      }
      retain = 6
      task   = "backup"
    }
  }

  depends_on = [helm_release.longhorn]
}

import {
  to = kubernetes_manifest.longhorn_recurring_job_daily_backup
  id = "apiVersion=longhorn.io/v1beta2,kind=RecurringJob,namespace=longhorn-system,name=daily-backup"
}

resource "kubernetes_manifest" "longhorn_recurring_job_fstrim" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "RecurringJob"
    metadata = {
      name      = "fstrim"
      namespace = kubernetes_namespace.longhorn_system.metadata[0].name
    }
    spec = {
      concurrency = 4
      cron        = "0 4 * * *"
      groups      = ["default"]
      labels      = {}
      name        = "fstrim"
      parameters  = {}
      retain      = 0
      task        = "filesystem-trim"
    }
  }

  depends_on = [helm_release.longhorn]
}

import {
  to = kubernetes_manifest.longhorn_recurring_job_fstrim
  id = "apiVersion=longhorn.io/v1beta2,kind=RecurringJob,namespace=longhorn-system,name=fstrim"
}

resource "kubernetes_manifest" "longhorn_recurring_job_system_backup" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "RecurringJob"
    metadata = {
      name      = "system-backup"
      namespace = kubernetes_namespace.longhorn_system.metadata[0].name
    }
    spec = {
      concurrency = 0
      cron        = "0 0 * * *"
      groups      = []
      labels      = {}
      name        = "system-backup"
      parameters = {
        volume-backup-policy = "if-not-present"
      }
      retain = 3
      task   = "system-backup"
    }
  }

  depends_on = [helm_release.longhorn]
}

import {
  to = kubernetes_manifest.longhorn_recurring_job_system_backup
  id = "apiVersion=longhorn.io/v1beta2,kind=RecurringJob,namespace=longhorn-system,name=system-backup"
}
