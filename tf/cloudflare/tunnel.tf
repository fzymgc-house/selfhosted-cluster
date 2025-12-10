# SPDX-License-Identifier: MIT
# terraform: language=hcl

# Create Cloudflare Tunnel
resource "cloudflare_zero_trust_tunnel_cloudflared" "main" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "main" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.main.id
}

# Configure tunnel ingress rules
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "main" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.main.id

  config = {
    ingress = concat(
      [for svc, definition in var.webhook_services : {
        hostname = "${svc}.${var.webhook_base_domain}"
        service  = definition.service_url

        origin_request = {
          http_host_header   = "${svc}.${var.webhook_base_domain}"
          origin_server_name = split("//", definition.service_url)[1]
          no_tls_verify      = false
        }
      }],
      [{
        service = "http_status:404"
      }]
    )
  }
}

# Create DNS records for webhook service subdomains
resource "cloudflare_dns_record" "webhook_services" {
  for_each = var.webhook_services

  zone_id = data.cloudflare_zone.fzymgc_house.id
  name    = "${each.key}.wh"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.main.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  comment = "${each.key} webhook endpoint via ${var.tunnel_name} tunnel"
  ttl     = 1 // automatic
}

# Store tunnel credentials in Vault
resource "vault_kv_secret_v2" "tunnel_credentials" {
  mount = "secret"
  name  = "fzymgc-house/cluster/cloudflared/tunnels/${var.tunnel_name}"

  data_json = jsonencode({
    account_tag = var.cloudflare_account_id
    tunnel_id   = cloudflare_zero_trust_tunnel_cloudflared.main.id
    tunnel_name = cloudflare_zero_trust_tunnel_cloudflared.main.name
    # Full token for cloudflared tunnel run --token or TUNNEL_TOKEN env var
    # This is computed by Cloudflare and works with token-based auth
    tunnel_token = data.cloudflare_zero_trust_tunnel_cloudflared_token.main.token
  })

  # Don't delete from Vault when destroying in Terraform
  # This prevents accidental credential loss
  custom_metadata {
    max_versions = 10
    data = {
      managed_by = "terraform"
      purpose    = "cloudflare-tunnel"
    }
  }
}
