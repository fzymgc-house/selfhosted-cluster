# Custom GitHub Actions Runner Image Design

## Overview

Build a custom GitHub Actions runner image with internal CA certificates and pre-installed tools, published to `ghcr.io/fzymgc-house/actions-runner`.

## Problem

The default `ghcr.io/actions/actions-runner` image lacks:
- Trust for our internal PKI (vault.fzymgc.house, etc.)
- Common tools (vault, jq, gh) requiring runtime installation

This causes workflow failures and slow builds due to repeated `apt-get install` calls.

## Solution

Build a custom image that:
1. Includes all CA certificates from our Vault PKI
2. Pre-installs vault CLI, jq, and gh CLI
3. Supports multi-arch (amd64 + arm64)

## File Structure

```
images/
└── actions-runner/
    ├── Dockerfile
    ├── certs/
    │   ├── fzymgc-root-ca.crt
    │   ├── fzymgc-intermediate-ca1.crt
    │   ├── fzymgc-house-intermediate-ca1-v1.crt
    │   └── fzymgc-house-vault-intermediate-ca1-v1.crt
    ├── scripts/
    │   └── update-ca-certs.sh
    └── README.md

.github/workflows/
└── build-runner-image.yaml
```

## Workflow Design

### Build Strategy

Use [Runs-on.com](https://runs-on.com/docs/) runners for native multi-arch builds:

```yaml
jobs:
  build-amd64:
    runs-on:
      - runs-on=${{ github.run_id }}/runner=4cpu-linux-x64/image=ubuntu24-full-x64/spot=lowest-price
    # Build and push ghcr.io/fzymgc-house/actions-runner:2.320.0-amd64

  build-arm64:
    runs-on:
      - runs-on=${{ github.run_id }}/runner=4cpu-linux-arm64/image=ubuntu24-full-arm64/spot=lowest-price
    # Build and push ghcr.io/fzymgc-house/actions-runner:2.320.0-arm64

  create-manifest:
    needs: [build-amd64, build-arm64]
    runs-on: ubuntu-latest
    # Combine into multi-arch manifest at ghcr.io/fzymgc-house/actions-runner:2.320.0
```

### Triggers

- **On push to main**: When files in `images/actions-runner/` change
- **Manual dispatch**: For picking up base image updates

## Dockerfile

```dockerfile
ARG RUNNER_VERSION=2.320.0
FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

USER root

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    gnupg \
    lsb-release \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install HashiCorp Vault CLI
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
      | tee /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update && apt-get install -y vault \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Add CA certificates
COPY certs/*.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

USER runner
```

## CA Certificate Management

### Storage

CA certificates are committed to the repository at `images/actions-runner/certs/`. This is appropriate because:
- CA certificates are public trust anchors, not secrets
- Eliminates build-time dependency on Vault availability
- Provides reproducible builds

### Update Script

`images/actions-runner/scripts/update-ca-certs.sh`:

```bash
#!/usr/bin/env bash
# Downloads all CA certs from Vault PKI mount
# Requires: vault CLI, VAULT_ADDR, authenticated session, and PKI trusted

set -euo pipefail

PKI_MOUNT="fzymgc-house/v1/ica1/v1"
CERT_DIR="$(dirname "$0")/../certs"

mkdir -p "$CERT_DIR"

# List all issuers and download their certs
for issuer in $(vault list -format=json "${PKI_MOUNT}/issuers" | jq -r '.[]'); do
  issuer_name=$(vault read -format=json "${PKI_MOUNT}/issuer/${issuer}" | jq -r '.data.issuer_name')
  echo "Downloading: ${issuer_name}"
  vault read -field=certificate "${PKI_MOUNT}/issuer/${issuer}" > "${CERT_DIR}/${issuer_name}.crt"
done

echo "Updated certs in ${CERT_DIR}:"
ls -la "$CERT_DIR"
```

### When to Update Certificates

| Event | Action Required |
|-------|-----------------|
| Root CA rotation | Run update script, rebuild image, redeploy runners |
| Intermediate CA added | Run update script, rebuild image |
| Intermediate CA revoked | Run update script, rebuild image |
| Regular maintenance | No action needed until expiration approaches |

**Current root CA expiration**: January 2033

### Impact of Root CA Change

A root CA change is a significant event requiring:

1. **Update certificates**: Run `update-ca-certs.sh` from a trusted machine
2. **Rebuild runner image**: Merge cert changes, workflow triggers rebuild
3. **Redeploy ARC runners**: ArgoCD syncs new image tag
4. **Cluster-wide impact**: All workloads trusting the old root must be updated
5. **Transition period**: Consider keeping both old and new roots during migration

## ARC Runner Configuration

After image is built, update `argocd/app-configs/arc-runners/values.yaml`:

```yaml
template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/fzymgc-house/actions-runner:2.320.0
        command: ["/home/runner/run.sh"]
        resources:
          limits:
            cpu: "2"
            memory: 4Gi
          requests:
            cpu: "500m"
            memory: 1Gi
```

The current `NODE_EXTRA_CA_CERTS`, `VAULT_CACERT` environment variables and `fzymgc-root-ca` volume mount become unnecessary.

## Implementation Checklist

- [ ] Create `images/actions-runner/` directory structure
- [ ] Write Dockerfile
- [ ] Create `update-ca-certs.sh` script
- [ ] Run script to populate initial certs
- [ ] Create `build-runner-image.yaml` workflow
- [ ] Build and push initial image
- [ ] Update ARC runner values to use new image
- [ ] Remove CA cert volume mount and env vars from ARC config
- [ ] Test workflows that use vault-action
- [ ] Update `images/actions-runner/README.md` with maintenance docs
