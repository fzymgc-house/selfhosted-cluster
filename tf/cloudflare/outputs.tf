# SPDX-License-Identifier: MIT
# terraform: language=hcl

output "tunnel_id" {
  description = "ID of the created Cloudflare Tunnel"
  value       = cloudflare_zero_trust_tunnel_cloudflared.main.id
}

output "tunnel_cname" {
  description = "CNAME target for the tunnel"
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.main.id}.cfargotunnel.com"
}

output "webhook_urls" {
  description = "Public webhook URLs for each service"
  value = {
    for service in keys(var.webhook_services) :
    service => "https://${service}.${var.webhook_base_domain}"
  }
}

output "vault_path" {
  description = "Vault path where tunnel credentials are stored"
  value       = vault_kv_secret_v2.tunnel_credentials.path
}
