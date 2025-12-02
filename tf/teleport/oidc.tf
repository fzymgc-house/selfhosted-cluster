// oidc.tf - OIDC connector for Authentik integration

# Retrieve OIDC client secret from Vault
data "vault_kv_secret_v2" "teleport_oidc" {
  mount = "secret"
  name  = "fzymgc-house/cluster/teleport/oidc"
}

# OIDC connector for Authentik SSO
resource "teleport_oidc_connector" "authentik" {
  version = "v3"
  metadata = {
    name = "authentik"
  }

  spec = {
    display       = "Authentik SSO"
    client_id     = data.vault_kv_secret_v2.teleport_oidc.data["client_id"]
    client_secret = data.vault_kv_secret_v2.teleport_oidc.data["client_secret"]
    issuer_url    = var.authentik_issuer_url
    redirect_url  = ["https://${var.teleport_public_addr}/v1/webapi/oidc/callback"]

    # Map Authentik groups to Teleport roles
    claims_to_roles = [
      {
        claim = "groups"
        value = "teleport-admins"
        roles = [teleport_role.admin.metadata.name]
      },
      {
        claim = "groups"
        value = "teleport-users"
        roles = [teleport_role.access.metadata.name]
      }
    ]
  }
}
