# SPDX-License-Identifier: MIT
# terraform: language=hcl

# Generate random secret for tunnel authentication
resource "random_password" "tunnel_secret" {
  length  = 64
  special = false
}

# Create Cloudflare Tunnel
resource "cloudflare_tunnel" "main" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  secret     = base64encode(random_password.tunnel_secret.result)
}

# Configure tunnel ingress rules
resource "cloudflare_tunnel_config" "main" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_tunnel.main.id

  config {
    # Windmill webhook endpoints
    # Path rewriting (/windmill/* → /*) is handled by cloudflare_ruleset in path-rewrite.tf
    # This ensures Windmill receives root paths as expected
    ingress_rule {
      hostname = var.webhook_hostname
      path     = "/windmill/*"
      service  = "http://windmill.windmill.svc.cluster.local:8000"

      origin_request {
        http_host_header   = "windmill.windmill.svc.cluster.local"
        origin_server_name = "windmill.windmill.svc.cluster.local"
        no_tls_verify      = false
      }
    }

    # Catch-all rule (required by cloudflared)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# Create DNS record pointing to tunnel
resource "cloudflare_record" "webhook" {
  zone_id = data.cloudflare_zone.fzymgc_house.id
  name    = "wh"
  value   = "${cloudflare_tunnel.main.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  comment = "Webhook endpoint via ${var.tunnel_name} tunnel"
}

# Store tunnel credentials in Vault
resource "vault_kv_secret_v2" "tunnel_credentials" {
  mount = "secret"
  name  = "fzymgc-house/cluster/cloudflared/tunnels/${var.tunnel_name}"

  data_json = jsonencode({
    account_tag   = var.cloudflare_account_id
    tunnel_id     = cloudflare_tunnel.main.id
    tunnel_name   = cloudflare_tunnel.main.name
    tunnel_secret = random_password.tunnel_secret.result
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
