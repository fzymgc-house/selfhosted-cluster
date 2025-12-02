// outputs.tf - Output values

output "admin_role_name" {
  description = "Name of the admin Teleport role"
  value       = teleport_role.admin.metadata.name
}

output "access_role_name" {
  description = "Name of the access Teleport role"
  value       = teleport_role.access.metadata.name
}

output "oidc_connector_name" {
  description = "Name of the OIDC connector"
  value       = teleport_oidc_connector.authentik.metadata.name
}
