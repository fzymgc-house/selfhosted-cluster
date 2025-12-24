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

### Vault Secret

Service account token stored at:
- **Path**: `secret/fzymgc-house/cluster/grafana/mcp-server`
- **Key**: `service_account_token`

Retrieve token:
```bash
vault kv get -field=service_account_token secret/fzymgc-house/cluster/grafana/mcp-server
```

### Terraform Resources

Service account managed in `tf/grafana/service-accounts.tf`:
- `grafana_service_account.mcp_server` - Viewer role service account
- `grafana_service_account_token.mcp_server` - Token for MCP authentication
- `vault_kv_secret_v2.grafana_mcp_token` - Token stored in Vault

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
