// variables.tf - Input variables for core-services module

variable "ldap_admin_username" {
  type = string
  description = "The username for the LDAP admin user"
}

variable "ldap_admin_password" {
  type = string
  description = "The password for the LDAP admin user"
}