// variables.tf - Input variables for core-services module

variable "authentik_client_id" {
  type = string
  description = "The client ID for the authentik application"
}

variable "authentik_client_secret" {
  type = string
  description = "The client secret for the authentik application"
}