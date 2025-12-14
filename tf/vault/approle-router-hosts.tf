# -*- coding: utf-8; mode: terraform -*-
# SPDX-License-Identifier: MIT
#
# AppRole authentication for router-hosts vault-agent.
# Enables vault-agent to authenticate and obtain tokens for certificate issuance.
#
# Post-apply steps:
#   vault read auth/approle/role/router-hosts-agent/role-id
#   vault write -f auth/approle/role/router-hosts-agent/secret-id
#
# See: https://github.com/fzymgc-house/router-hosts/tree/main/examples

resource "vault_approle_auth_backend_role" "router_hosts_agent" {
  backend        = vault_auth_backend.approle.path
  role_name      = "router-hosts-agent"
  token_policies = [vault_policy.router_hosts.name]

  # Short-lived tokens, auto-renewed by vault-agent
  token_ttl     = 3600  # 1 hour
  token_max_ttl = 86400 # 24 hours

  # Non-expiring secret_id for long-running service
  # Rotate manually if compromised
  secret_id_ttl      = 0
  secret_id_num_uses = 0
}
