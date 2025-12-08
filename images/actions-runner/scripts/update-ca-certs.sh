#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Downloads all CA certificates from Vault PKI mount
#
# Requirements:
#   - vault CLI installed and in PATH
#   - VAULT_ADDR environment variable set (defaults to https://vault.fzymgc.house)
#   - Authenticated vault session (vault login)
#   - PKI endpoint must be trusted (run from a machine that already trusts the CA)
#
# Usage:
#   ./update-ca-certs.sh
#
# The script will download all issuer certificates from the configured PKI mount
# and save them to the certs/ directory alongside this script.

set -euo pipefail

# Configuration
PKI_MOUNT="fzymgc-house/v1/ica1/v1"
VAULT_ADDR="${VAULT_ADDR:-https://vault.fzymgc.house}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="${SCRIPT_DIR}/../certs"

export VAULT_ADDR

echo "Vault address: ${VAULT_ADDR}"
echo "PKI mount: ${PKI_MOUNT}"
echo "Certificate directory: ${CERT_DIR}"
echo

# Verify vault is authenticated
if ! vault token lookup &>/dev/null; then
    echo "Error: Not authenticated to Vault. Run 'vault login' first."
    exit 1
fi

mkdir -p "${CERT_DIR}"

# List all issuers and download their certificates
echo "Fetching issuer list from ${PKI_MOUNT}/issuers..."
issuers=$(vault list -format=json "${PKI_MOUNT}/issuers" | jq -r '.[]')

for issuer in ${issuers}; do
    issuer_name=$(vault read -format=json "${PKI_MOUNT}/issuer/${issuer}" | jq -r '.data.issuer_name')

    if [[ -z "${issuer_name}" || "${issuer_name}" == "null" ]]; then
        echo "Warning: Issuer ${issuer} has no name, using ID as filename"
        issuer_name="${issuer}"
    fi

    echo "Downloading: ${issuer_name}"
    vault read -field=certificate "${PKI_MOUNT}/issuer/${issuer}" > "${CERT_DIR}/${issuer_name}.crt"
done

echo
echo "Updated certificates in ${CERT_DIR}:"
ls -la "${CERT_DIR}"

echo
echo "Done. Verify the certificates and commit the changes."
