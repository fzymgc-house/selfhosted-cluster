# Service accounts for external integrations (MCP server)
#
# Two accounts with different privilege levels:
# - mcp_viewer: Read-only access for queries and dashboard inspection
# - mcp_editor: Can create/modify dashboards and alerts

# Viewer service account (default for MCP operations)
resource "grafana_service_account" "mcp_viewer" {
  name        = "mcp-viewer"
  role        = "Viewer"
  is_disabled = false
}

resource "grafana_service_account_token" "mcp_viewer" {
  name               = "mcp-viewer-token"
  service_account_id = grafana_service_account.mcp_viewer.id
}

# Editor service account (for creating/modifying dashboards)
resource "grafana_service_account" "mcp_editor" {
  name        = "mcp-editor"
  role        = "Editor"
  is_disabled = false
}

resource "grafana_service_account_token" "mcp_editor" {
  name               = "mcp-editor-token"
  service_account_id = grafana_service_account.mcp_editor.id
}

# Store tokens in Vault for secure access
resource "vault_kv_secret_v2" "grafana_mcp_tokens" {
  mount = "secret"
  name  = "fzymgc-house/cluster/grafana/mcp-server"

  data_json = jsonencode({
    viewer_token = grafana_service_account_token.mcp_viewer.key
    editor_token = grafana_service_account_token.mcp_editor.key
  })
}
