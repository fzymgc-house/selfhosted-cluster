// variables.tf - Input variables for core-services module

variable "ldap_admin_password" {
  type = string
  description = "The password for the LDAP admin user"
}