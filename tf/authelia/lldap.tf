// lldap.tf - LDAP authentication backend for Authelia

// Import the resource if it exists
import {
  id = "ldap"
  to = vault_ldap_auth_backend.lldap
}

// Create LDAP authentication backend for Authelia
resource "vault_ldap_auth_backend" "lldap" {
  path = "ldap"
  url = "ldaps://lldap.lldap"
  binddn = "cn=${var.ldap_admin_username},dc=fzymgc,dc=house"
  bindpass = var.ldap_admin_password
  userdn = "ou=users,dc=fzymgc,dc=house"
  userattr = "uid"
  username_as_alias = true
  groupdn = "ou=groups,dc=fzymgc,dc=house"
  groupattr = "cn"
  groupfilter = "(|(memberUid={{.UserDN}})(member={{.UserDN}}))"
}