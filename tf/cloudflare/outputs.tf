# SPDX-License-Identifier: MIT
# terraform: language=hcl

output "tunnel_id" {
  description = "ID of the created Cloudflare Tunnel"
  value       = cloudflare_tunnel.main.id
}

output "tunnel_cname" {
  description = "CNAME target for the tunnel"
  value       = "${cloudflare_tunnel.main.id}.cfargotunnel.com"
}

output "webhook_url" {
  description = "Public webhook URL"
  value       = "https://${var.webhook_hostname}"
}

output "vault_path" {
  description = "Vault path where tunnel credentials are stored"
  value       = vault_kv_secret_v2.tunnel_credentials.path
}
