# MCP Servers

Configuration and management of Model Context Protocol (MCP) servers for AI assistant integration.

## Grafana MCP Server

Enables AI assistants to query Grafana dashboards, data sources, and metrics.

### Installation

```bash
go install github.com/grafana/mcp-grafana/cmd/mcp-grafana@latest
```

### Configuration

Add to Claude Code settings (`~/.claude.json` or project `.mcp.json`):

```json
{
  "mcpServers": {
    "grafana": {
      "command": "mcp-grafana",
      "env": {
        "GRAFANA_URL": "https://grafana.fzymgc.house",
        "GRAFANA_SERVICE_ACCOUNT_TOKEN": "<token-from-vault>"
      }
    }
  }
}
```

### Vault Secrets

Two tokens with different privilege levels:

| Key | Role | Use For |
|-----|------|---------|
| `viewer_token` | Viewer | Queries, dashboard inspection (default) |
| `editor_token` | Editor | Creating/modifying dashboards and alerts |

**Path**: `secret/fzymgc-house/cluster/grafana/mcp-server`

Retrieve tokens:
```bash
# Viewer (recommended for most operations)
vault kv get -field=viewer_token secret/fzymgc-house/cluster/grafana/mcp-server

# Editor (when modifications needed)
vault kv get -field=editor_token secret/fzymgc-house/cluster/grafana/mcp-server
```

### Terraform Resources

Service accounts managed in `tf/grafana/service-accounts.tf`:
- `grafana_service_account.mcp_viewer` - Viewer role (read-only)
- `grafana_service_account.mcp_editor` - Editor role (read/write)
- `vault_kv_secret_v2.grafana_mcp_tokens` - Both tokens stored in Vault

### Capabilities

| Tool | Purpose |
|------|---------|
| `search_dashboards` | Find dashboards by name/tag |
| `get_dashboard_by_uid` | Retrieve dashboard JSON |
| `list_datasources` | List configured data sources |
| `query_prometheus` | Execute PromQL queries |
| `query_loki` | Execute LogQL queries |
| `list_incidents` | List Grafana IRM incidents |

## Kubernetes MCP Server

Cluster investigation in readonly mode. See [kubernetes-mcp-server](https://github.com/strowk/mcp-k8s-go).

### Configuration

```json
{
  "mcpServers": {
    "kubernetes-mcp-server": {
      "command": "mcp-k8s",
      "args": ["--context", "fzymgc-house"]
    }
  }
}
```

## Adding New MCP Servers

1. Install the MCP server binary
2. Store any credentials in Vault at `secret/fzymgc-house/cluster/<service>/mcp-server`
3. Add configuration to Claude Code settings
4. Update CLAUDE.md MCP Servers table
5. Document configuration in this file
