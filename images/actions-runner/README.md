# Custom GitHub Actions Runner Image

Custom GitHub Actions runner image with internal CA certificates and pre-installed tools.

**Image**: `ghcr.io/fzymgc-house/actions-runner`

## Features

- **Internal PKI Trust**: Pre-installed CA certificates for `vault.fzymgc.house` and other internal services
- **Pre-installed Tools**: vault CLI, jq, gh CLI
- **Multi-arch**: Supports amd64 and arm64

## Pre-installed Tools

| Tool | Purpose |
|------|---------|
| vault | HashiCorp Vault CLI for secrets management |
| jq | JSON processing |
| gh | GitHub CLI |

## CA Certificates

The following CA certificates are included:

- `fzymgc-root-ca.crt` - Root CA (expires January 2033)
- `fzymgc-intermediate-ca1.crt` - Intermediate CA
- `fzymgc-house-intermediate-ca1-v1.crt` - House intermediate CA
- `fzymgc-house-vault-intermediate-ca1-v1.crt` - Vault intermediate CA

## Building

The image is automatically built when changes are pushed to `images/actions-runner/` on the main branch.

To manually trigger a build:

1. Go to Actions → "Build Actions Runner Image"
2. Click "Run workflow"
3. Optionally specify a different runner version

## Updating CA Certificates

When CA certificates need to be updated (e.g., new intermediate CA, root rotation):

### Prerequisites

- vault CLI installed locally
- Authenticated to Vault (`vault login`)
- Network access to `vault.fzymgc.house`
- Existing CA trust (run from a machine that already trusts our PKI)

### Update Process

```bash
# From the repository root
./images/actions-runner/scripts/update-ca-certs.sh

# Review the downloaded certificates
ls -la images/actions-runner/certs/

# Commit and push to trigger a rebuild
git add images/actions-runner/certs/
git commit -m "chore: Update CA certificates"
git push
```

### When to Update

| Event | Action Required |
|-------|-----------------|
| Root CA rotation | Update certs, rebuild image, redeploy ARC runners |
| Intermediate CA added | Update certs, rebuild image |
| Intermediate CA revoked | Update certs, rebuild image |
| Regular maintenance | No action needed until expiration approaches |

### Root CA Rotation Impact

A root CA change is a significant event requiring:

1. **Update certificates**: Run `update-ca-certs.sh` from a trusted machine
2. **Rebuild runner image**: Merge cert changes to main, workflow triggers rebuild
3. **Redeploy ARC runners**: Update `argocd/app-configs/arc-runners/values.yaml` with new image tag
4. **Cluster-wide impact**: All workloads trusting the old root must be updated
5. **Transition period**: Consider keeping both old and new roots during migration

## ARC Runner Configuration

After building a new image, update `argocd/app-configs/arc-runners/values.yaml`:

```yaml
template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/fzymgc-house/actions-runner:2.320.0
        command: ["/home/runner/run.sh"]
```

With this custom image, the following environment variables and volume mounts become unnecessary and can be removed:
- `NODE_EXTRA_CA_CERTS`
- `VAULT_CACERT`
- `fzymgc-root-ca` volume mount

## Version Compatibility

The image version corresponds to the upstream `ghcr.io/actions/actions-runner` version. When upgrading:

1. Check [actions/runner releases](https://github.com/actions/runner/releases)
2. Trigger manual workflow with new version
3. Update ARC runner configuration to use new tag

## Troubleshooting

### TLS Certificate Errors

**Symptom**: `certificate signed by unknown authority` or `unable to verify the first certificate`

**Cause**: The runner pod is using an older image without current CA certificates.

**Solution**:
1. Verify the image tag in `argocd/app-configs/arc-runners/values.yaml` matches the latest build
2. Check if CA certificates need updating: `./images/actions-runner/scripts/update-ca-certs.sh`
3. Force a pod restart: `kubectl --context fzymgc-house rollout restart deployment -n arc-runners`

### Vault Authentication Failures

**Symptom**: `vault-action` step fails with connection or auth errors

**Cause**: Vault CLI can't connect to `vault.fzymgc.house` or AppRole credentials are invalid.

**Solution**:
1. Verify CA trust: `curl -v https://vault.fzymgc.house/v1/sys/health` from a runner
2. Check AppRole secrets are configured in GitHub repository settings
3. Verify Vault policies allow the AppRole to access required paths

### Tools Not Found

**Symptom**: `command not found: vault` or `command not found: jq`

**Cause**: Workflow is running on a different runner (not the custom image) or image pull failed.

**Solution**:
1. Confirm workflow uses `runs-on: fzymgc-house-cluster-runners`
2. Check runner pod logs: `kubectl --context fzymgc-house logs -n arc-runners -l app=arc-runner`
3. Verify image pull succeeded: `kubectl --context fzymgc-house describe pod -n arc-runners -l app=arc-runner`

### Image Pull Failures

**Symptom**: Runner pods stuck in `ImagePullBackOff` or `ErrImagePull`

**Cause**: GHCR authentication issues or image doesn't exist.

**Solution**:
1. Verify image exists: `gh api /user/packages/container/actions-runner/versions --jq '.[0].metadata.container.tags'`
2. Check GHCR pull secret: `kubectl --context fzymgc-house get secret -n arc-runners ghcr-login-secret`
3. Trigger a manual image build if the tag doesn't exist
