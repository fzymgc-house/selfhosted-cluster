# variables.tf - Input variables for authentik module

variable "vault_addr" {
  description = "Vault server address"
  type        = string
  default     = "https://vault.fzymgc.house"
}

variable "tfc_vault_dynamic_credentials" {
  description = "HCP TF dynamic credentials for Vault (injected when TFC_VAULT_PROVIDER_AUTH=true)"
  type = object({
    default = object({
      token_filename = string
      address        = string
      namespace      = string
      ca_cert_file   = string
    })
    aliases = map(object({
      token_filename = string
      address        = string
      namespace      = string
      ca_cert_file   = string
    }))
  })
  default = null

  validation {
    condition = (
      var.tfc_vault_dynamic_credentials == null ||
      try(var.tfc_vault_dynamic_credentials.default.token_filename, "") != ""
    )
    error_message = "tfc_vault_dynamic_credentials.default.token_filename is required when dynamic credentials are provided."
  }
}
