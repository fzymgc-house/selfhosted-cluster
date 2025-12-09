# SPDX-License-Identifier: MIT
# terraform: language=hcl

# Generate random secret for tunnel authentication
resource "random_password" "tunnel_secret" {
  length  = 64
  special = false
}

# Create Cloudflare Tunnel
resource "cloudflare_zero_trust_tunnel_cloudflared" "main" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  secret     = base64encode(random_password.tunnel_secret.result)

  # Prevent tunnel recreation if secret changes
  # The tunnel_token is computed by Cloudflare and remains valid
  lifecycle {
    ignore_changes = [secret]
  }
}

# Configure tunnel ingress rules
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "main" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.main.id

  config {
    # Dynamic ingress rules for webhook services
    # Each service gets its own subdomain: service.wh.fzymgc.house
    dynamic "ingress_rule" {
      for_each = var.webhook_services
      content {
        hostname = "${ingress_rule.key}.${var.webhook_base_domain}"
        service  = ingress_rule.value.service_url

        origin_request {
          http_host_header   = "${ingress_rule.key}.${var.webhook_base_domain}"
          origin_server_name = split("//", ingress_rule.value.service_url)[1]
          no_tls_verify      = false
        }
      }
    }

    # Catch-all rule (required by cloudflared)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# Create DNS records for webhook service subdomains
resource "cloudflare_record" "webhook_services" {
  for_each = var.webhook_services

  zone_id = data.cloudflare_zone.fzymgc_house.id
  name    = "${each.key}.wh"
  value   = "${cloudflare_zero_trust_tunnel_cloudflared.main.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  comment = "${each.key} webhook endpoint via ${var.tunnel_name} tunnel"
}

# Store tunnel credentials in Vault
resource "vault_kv_secret_v2" "tunnel_credentials" {
  mount = "secret"
  name  = "fzymgc-house/cluster/cloudflared/tunnels/${var.tunnel_name}"

  data_json = jsonencode({
    account_tag  = var.cloudflare_account_id
    tunnel_id    = cloudflare_zero_trust_tunnel_cloudflared.main.id
    tunnel_name  = cloudflare_zero_trust_tunnel_cloudflared.main.name
    # Full token for cloudflared tunnel run --token or TUNNEL_TOKEN env var
    # This is computed by Cloudflare and works with token-based auth
    tunnel_token = cloudflare_zero_trust_tunnel_cloudflared.main.tunnel_token
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
