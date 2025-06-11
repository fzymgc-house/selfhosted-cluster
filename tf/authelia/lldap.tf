resource "vault_ldap_auth_backend" "lldap" {
  path = "ldap"
  url = "ldaps://lldap.lldap"
  binddn = "cn=admin,dc=fzymgc,dc=house"
  bindpass = var.vault_ldap_admin_password
  userdn = "ou=users,dc=fzymgc,dc=house"
  userattr = "uid"
  groupdn = "ou=groups,dc=fzymgc,dc=house"
  groupattr = "cn"
  groupfilter = "(|(memberUid={{.UserDN}})(member={{.UserDN}}))"
}