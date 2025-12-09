# SPDX-License-Identifier: MIT
# terraform: language=hcl

# Create Cloudflare Tunnel (remotely-managed via Cloudflare dashboard)
resource "cloudflare_zero_trust_tunnel_cloudflared" "main" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  config_src = "cloudflare" # Manage tunnel configuration remotely
}

# Read tunnel token for cloudflared authentication
data "cloudflare_zero_trust_tunnel_cloudflared_token" "main" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.main.id
}

# Configure tunnel ingress rules (managed in Cloudflare)
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "main" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.main.id

  config = {
    # Dynamic ingress rules for webhook services
    # Each service gets its own subdomain: service.wh.fzymgc.house
    ingress = concat(
      [
        for key, service in var.webhook_services : {
          hostname = "${key}.${var.webhook_base_domain}"
          service  = service.service_url
          origin_request = {
            http_host_header   = "${key}.${var.webhook_base_domain}"
            origin_server_name = split("//", service.service_url)[1]
            no_tls_verify      = false
          }
        }
      ],
      # Catch-all rule (required by cloudflared)
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
  ttl     = 1
}

# Store tunnel credentials in Vault
# Note: The tunnel token contains all necessary authentication information
resource "vault_kv_secret_v2" "tunnel_credentials" {
  mount = "secret"
  name  = "fzymgc-house/cluster/cloudflared/tunnels/${var.tunnel_name}"

  data_json = jsonencode({
    account_tag  = var.cloudflare_account_id
    tunnel_id    = cloudflare_zero_trust_tunnel_cloudflared.main.id
    tunnel_name  = cloudflare_zero_trust_tunnel_cloudflared.main.name
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
