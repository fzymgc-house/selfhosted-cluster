# ArgoCD OAuth2/OIDC Integration
# Provides single sign-on for ArgoCD GitOps platform

# Groups for ArgoCD access control
resource "authentik_group" "argocd_user" {
  name = "argocd-user"
}

resource "authentik_group" "argocd_admin" {
  name = "argocd-admin"
}

resource "authentik_group" "cluster_admin" {
  name = "cluster-admin"
}
