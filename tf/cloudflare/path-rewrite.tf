# SPDX-License-Identifier: MIT
# terraform: language=hcl

# Create Transform Rule to strip /windmill prefix
# Windmill expects root paths, but public webhooks use wh.fzymgc.house/windmill/*
resource "cloudflare_ruleset" "windmill_path_rewrite" {
  zone_id     = data.cloudflare_zone.fzymgc_house.id
  name        = "Windmill webhook path rewriting"
  description = "Strip /windmill prefix before forwarding to origin"
  kind        = "zone"
  phase       = "http_request_transform"

  rules {
    ref         = "windmill_strip_prefix"
    description = "Rewrite /windmill/* to /* for Windmill origin"
    expression  = "(http.host eq \"${var.webhook_hostname}\" and starts_with(http.request.uri.path, \"/windmill/\"))"
    action      = "rewrite"

    action_parameters {
      uri {
        path {
          # Use regex_replace to strip /windmill prefix
          # Input: /windmill/api/version → Output: /api/version
          expression = "regex_replace(http.request.uri.path, \"^/windmill(/.*)\", \"${1}\")"
        }
      }
    }
  }
}
