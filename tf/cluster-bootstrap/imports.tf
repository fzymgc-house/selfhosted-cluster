// imports.tf - Import blocks for existing resources

# Namespaces
import {
  to = kubernetes_namespace.prometheus
  id = "prometheus"
}

import {
  to = kubernetes_namespace.cert_manager
  id = "cert-manager"
}

import {
  to = kubernetes_namespace.external_secrets
  id = "external-secrets"
}

import {
  to = kubernetes_namespace.longhorn_system
  id = "longhorn-system"
}

import {
  to = kubernetes_namespace.argocd
  id = "argocd"
}

import {
  to = kubernetes_namespace.metallb
  id = "metallb"
}

# Helm Releases
import {
  to = helm_release.prometheus_operator_crds
  id = "prometheus/prometheus-operator-crds"
}

import {
  to = helm_release.cert_manager
  id = "cert-manager/cert-manager"
}

import {
  to = helm_release.external_secrets_operator
  id = "external-secrets/external-secrets-operator"
}

import {
  to = helm_release.longhorn
  id = "longhorn-system/longhorn"
}

import {
  to = helm_release.metallb
  id = "metallb/metallb"
}

import {
  to = helm_release.argocd
  id = "argocd/argocd"
}

# Kubernetes Secrets
import {
  to = kubernetes_secret.fzymgc_house_ica1_key
  id = "cert-manager/fzymgc-house-ica1-key"
}

import {
  to = kubernetes_secret.argocd_oidc_secret
  id = "argocd/argocd-oidc-secret"
}

import {
  to = kubernetes_secret.argocd_selfhosted_repo
  id = "argocd/argocd-selfhosted-repo"
}

import {
  to = kubernetes_secret.longhorn_crypto_config
  id = "longhorn-system/longhorn-crypto-config"
}

import {
  to = kubernetes_secret.longhorn_backup_creds
  id = "longhorn-system/longhorn-backup-creds"
}

import {
  to = kubernetes_secret.vault_ca_chain
  id = "external-secrets/vault-ca-chain"
}

# Storage Classes
import {
  to = kubernetes_storage_class.longhorn_encrypted
  id = "longhorn-encrypted"
}

import {
  to = kubernetes_storage_class.longhorn_1replica_encrypted
  id = "longhorn-1replica-encrypted"
}

# Kubernetes Manifests
import {
  to = kubernetes_manifest.vault_cluster_secret_store
  id = "apiVersion=external-secrets.io/v1,kind=ClusterSecretStore,name=vault"
}

import {
  to = kubernetes_manifest.fzymgc_house_issuer
  id = "apiVersion=cert-manager.io/v1,kind=ClusterIssuer,name=fzymgc-house-issuer"
}

import {
  to = kubernetes_manifest.metallb_ip_address_pool
  id = "apiVersion=metallb.io/v1beta1,kind=IPAddressPool,namespace=metallb,name=default"
}

import {
  to = kubernetes_manifest.metallb_l2_advertisement
  id = "apiVersion=metallb.io/v1beta1,kind=L2Advertisement,namespace=metallb,name=default"
}

import {
  to = kubernetes_manifest.argocd_secret_external
  id = "apiVersion=external-secrets.io/v1,kind=ExternalSecret,namespace=argocd,name=argocd-secret"
}

import {
  to = kubernetes_manifest.cluster_app
  id = "apiVersion=argoproj.io/v1alpha1,kind=Application,namespace=argocd,name=cluster-app"
}

# Longhorn Recurring Jobs
import {
  to = kubernetes_manifest.longhorn_recurring_job_backup_snapshot_cleanup
  id = "apiVersion=longhorn.io/v1beta2,kind=RecurringJob,namespace=longhorn-system,name=backup-snapshot-cleanup"
}

import {
  to = kubernetes_manifest.longhorn_recurring_job_daily_backup
  id = "apiVersion=longhorn.io/v1beta2,kind=RecurringJob,namespace=longhorn-system,name=daily-backup"
}

import {
  to = kubernetes_manifest.longhorn_recurring_job_fstrim
  id = "apiVersion=longhorn.io/v1beta2,kind=RecurringJob,namespace=longhorn-system,name=fstrim"
}

import {
  to = kubernetes_manifest.longhorn_recurring_job_system_backup
  id = "apiVersion=longhorn.io/v1beta2,kind=RecurringJob,namespace=longhorn-system,name=system-backup"
}
