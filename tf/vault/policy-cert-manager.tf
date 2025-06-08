import {
  id = "cert-manager"
  to = vault_policy.cert-manager
}

resource "vault_policy" "cert-manager" {
  name   = "cert-manager"
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

path "fzymgc-house/v1/ica1/v1/cert/cert-manager" {
  capabilities = ["read","list"]
}

path "fzymgc-house/v1/ica1/v1/issue/cert-manager" {
  capabilities = ["create","update"]
}

path "fzymgc-house/v1/ica1/v1/issuer/+/issue/cert-manager" {
  capabilities = ["create","update"]
}

path "fzymgc-house/v1/ica1/v1/sign/cert-manager" {
  capabilities = ["create","update"]
}

path "fzymgc-house/v1/ica1/v1/issuer/+/sign/cert-manager" {
  capabilities = ["create","update"]
}

path "fzymgc-house/v1/ica1/v1/revoke" {
  capabilities = ["create","update"]
}

path "fzymgc-house/v1/ica1/v1/revoke-with-key" {
  capabilities = ["create","update"]
}
EOT
}

import {
  id = "certmanager_vault-issuer"
  to = vault_policy.certmanager_vault-issuer
}

resource "vault_policy" "certmanager_vault-issuer" {
  name   = "certmanager_vault-issuer"
  policy = <<EOT
path "fzymgc-house/+/issue/*" {
  capabilities = ["create", "read", "update"]
}
path "fzymgc-house/+/role/*" {
  capabilities = ["read"]
}
path "fzymgc-house/+/roles" {
  capabilities = ["read"]
}
path "fzymgc-house/+/roles/" {
  capabilities = ["read","list"]
}
EOT
}
