# Grafana OAuth2/OIDC Integration
# Provides single sign-on for Grafana metrics and monitoring platform

# Groups for Grafana access control
resource "authentik_group" "grafana_editor" {
  name = "grafana-editor"
}

resource "authentik_group" "grafana_admin" {
  name         = "grafana-admin"
  parent       = authentik_group.grafana_editor.id
  is_superuser = false
}
