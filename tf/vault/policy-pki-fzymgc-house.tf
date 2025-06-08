import {
  to = vault_policy.pki-fzymgc-house
  id = "pki-fzymgc-house"
}

resource "vault_policy" "pki-fzymgc-house" {
  name   = "pki-fzymgc-house"
  policy = <<EOT

path "fzymgc-house/v1/ica1/v1/roles" {
  capabilities = ["read","list"]
}

path "fzymgc-house/v1/ica1/v1/certs/revoked" {
  capabilities = ["read","list"]
}

path "fzymgc-house/v1/ica1/v1/certs/unified-revoked" {
  capabilities = ["read","list"]
}

path "fzymgc-house/v1/ica1/v1/certs/revocation-queue" {
  capabilities = ["read","list"]
}

path "fzymgc-house/v1/ica1/v1/issuers" {
  capabilities = ["read","list"]
}

path "fzymgc-house/v1/ica1/v1/cert/ca" {
  capabilities = ["read","list"]
}

path "fzymgc-house/v1/ica1/v1/ca" {
  capabilities = ["read","list"]
}

path "fzymgc-house/v1/ica1/v1/ca/*" {
  capabilities = ["read","list"]
}

path "fzymgc-house/v1/ica1/v1/issuer/+/json" {
  capabilities = ["read","list"]
}

path "fzymgc-house/v1/ica1/v1/issuer/+/der" {
  capabilities = ["read","list"]
}

path "fzymgc-house/v1/ica1/v1/issuer/+/pem" {
  capabilities = ["read","list"]
}

path "fzymgc-house/v1/ica1/v1/ca_chain" {
  capabilities = ["read","list"]
}

path "fzymgc-house/v1/ica1/v1/revoke" {
  capabilities = ["create","update"]
}

path "fzymgc-house/v1/ica1/v1/revoke-with-key" {
  capabilities = ["create","update"]
}

path "fzymgc-house/v1/ica1/v1/cert/unrestricted-ec" {
  capabilities = ["read","list"]
}

path "fzymgc-house/v1/ica1/v1/issue/unrestricted-ec" {
  capabilities = ["create","update"]
}

path "fzymgc-house/v1/ica1/v1/issuer/+/issue/unrestricted-ec" {
  capabilities = ["create","update"]
}

path "fzymgc-house/v1/ica1/v1/sign/unrestricted-ec" {
  capabilities = ["create","update"]
}

path "fzymgc-house/v1/ica1/v1/issuer/+/sign/unrestricted-ec" {
  capabilities = ["create","update"]
}

EOT
}
