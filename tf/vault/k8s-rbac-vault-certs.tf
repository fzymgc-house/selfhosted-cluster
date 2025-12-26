# tf/vault/k8s-rbac-vault-certs.tf
# Kubernetes RBAC bindings for Vault-issued certificate groups.
# Maps certificate Organization field to ClusterRoles.

resource "kubernetes_cluster_role_binding_v1" "vault_cert_admins" {
  metadata {
    name = "vault-cert-cluster-admins"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "rbac"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "Group"
    name      = "k8s-admins"
    api_group = "rbac.authorization.k8s.io"
  }
}

resource "kubernetes_cluster_role_binding_v1" "vault_cert_developers" {
  metadata {
    name = "vault-cert-developers"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "rbac"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "edit"
  }

  subject {
    kind      = "Group"
    name      = "k8s-developers"
    api_group = "rbac.authorization.k8s.io"
  }
}

resource "kubernetes_cluster_role_binding_v1" "vault_cert_viewers" {
  metadata {
    name = "vault-cert-viewers"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "rbac"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "view"
  }

  subject {
    kind      = "Group"
    name      = "k8s-viewers"
    api_group = "rbac.authorization.k8s.io"
  }
}
