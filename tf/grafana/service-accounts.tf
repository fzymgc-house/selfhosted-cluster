# Service accounts for external integrations

# MCP Server service account for AI assistant access
resource "grafana_service_account" "mcp_server" {
  name        = "mcp-server"
  role        = "Viewer"
  is_disabled = false
}

resource "grafana_service_account_token" "mcp_server" {
  name               = "mcp-server-token"
  service_account_id = grafana_service_account.mcp_server.id
}

# Store token in Vault for secure access
resource "vault_kv_secret_v2" "grafana_mcp_token" {
  mount = "secret/fzymgc-house"
  name  = "cluster/grafana/mcp-server"

  data_json = jsonencode({
    service_account_token = grafana_service_account_token.mcp_server.key
  })
}
