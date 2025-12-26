# tf/authentik/kubernetes-groups.tf
# Authentik groups for Kubernetes access tiers.
# Users assigned to these groups receive corresponding Vault PKI policies
# via OIDC claims (see tf/vault/oidc-k8s-group-aliases.tf).

resource "authentik_group" "k8s_admins" {
  name         = "k8s-admins"
  is_superuser = false
}

resource "authentik_group" "k8s_developers" {
  name         = "k8s-developers"
  is_superuser = false
}

resource "authentik_group" "k8s_viewers" {
  name         = "k8s-viewers"
  is_superuser = false
}
