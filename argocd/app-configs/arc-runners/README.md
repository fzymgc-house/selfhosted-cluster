# GitHub Actions Runner Controller (ARC) - Runner Scale Set

This directory contains the configuration for the ARC runner scale set deployed to the `arc-runners` namespace.

## Architecture Overview

ARC uses a two-component architecture:

1. **Controller** (`arc-systems` namespace): Manages runner lifecycle, scales runners based on workflow demand
2. **Runner Scale Set** (`arc-runners` namespace): The actual ephemeral runner pods that execute workflows

## Version Information

| Component | Version | Chart |
|-----------|---------|-------|
| Controller | 0.13.0 | `gha-runner-scale-set-controller` |
| Runner Scale Set | 0.13.0 | `gha-runner-scale-set` |
| Runner Image | latest | `ghcr.io/actions/actions-runner` |

## Key Configuration Decisions

### Docker-in-Docker (dind) Mode

We use the **built-in `containerMode.type: "dind"`** which automatically configures:
- Docker daemon sidecar container
- Shared volumes for docker socket and work directory
- Proper security context for privileged operations

> **Note**: The `arc-runners` namespace requires `privileged` PodSecurity policy because the dind sidecar container requires `securityContext.privileged: true`.

### Authentication

We use **GitHub App authentication** instead of a Personal Access Token (PAT):

- More secure (no long-lived tokens)
- Better audit trail
- Scoped permissions

Credentials stored in Vault at `secret/fzymgc-house/cluster/github`:
- `github_org_app_id`: GitHub App ID
- `github_org_app_private_key`: Private key for the GitHub App
- `github_org_app_installation_id`: Installation ID for the organization

### Scaling Configuration

| Setting | Value | Rationale |
|---------|-------|-----------|
| `minRunners` | 0 | Scale to zero when idle (cost efficiency) |
| `maxRunners` | 3 | Conservative limit for homelab resources |

### Storage

Built-in dind mode uses `emptyDir` volumes for simplicity and reliability.

## Important Implementation Notes

### Explicit Command Required

When overriding the `template.spec` in values.yaml, you **must** specify the command explicitly:

```yaml
containers:
  - name: runner
    command: ["/home/runner/run.sh"]
```

The `ghcr.io/actions/actions-runner` image does not have a default ENTRYPOINT or CMD. Without the explicit command, the container will exit immediately with code 0.

This is documented in the [official GitHub documentation](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/deploying-runner-scale-sets-with-actions-runner-controller#configuring-the-runner-image).

### listenerMetrics Required in 0.13.0

Starting with version 0.13.0, the `listenerMetrics` field is required for the listener to start:

```yaml
listenerMetrics: {}
```

Without this, the listener pod will fail to start.

### controllerServiceAccount Configuration

The runner scale set needs to know which service account the controller uses:

```yaml
controllerServiceAccount:
  name: arc-controller-gha-rs-controller
  namespace: arc-systems
```

## Files

| File | Purpose |
|------|---------|
| `values.yaml` | Helm values for gha-runner-scale-set chart |
| `github-token-secret.yaml` | ExternalSecret for GitHub App credentials |
| `kustomization.yaml` | Kustomize configuration |
| `namespace.yaml` | Namespace definition |

## Troubleshooting

### Runners Exit Immediately

**Symptom**: Runner pods go from `ContainerCreating` → `Completed` in ~8 seconds without executing jobs.

**Cause**: Missing `command: ["/home/runner/run.sh"]` in the runner container spec.

**Solution**: Ensure the command is explicitly set in values.yaml.

### Listener Not Starting

**Symptom**: Listener pod fails to start or crashes.

**Cause**: Missing `listenerMetrics: {}` configuration (required in 0.13.0+).

**Solution**: Add `listenerMetrics: {}` to values.yaml.

### ExternalSecret Not Syncing

**Symptom**: `github-token` secret not created or showing sync errors.

**Check**:
```bash
kubectl --context fzymgc-house describe externalsecret github-token -n arc-runners
```

**Common Issues**:
- Vault path incorrect
- Secret keys don't match expected names
- ClusterSecretStore not configured

### Runner Pod Fails with PodSecurity Violation

**Symptom**: Runner pod fails to create with error: `violates PodSecurity "baseline:latest": privileged`

**Cause**: The namespace has `baseline` PodSecurity policy, but dind requires `privileged`.

**Solution**: Ensure namespace has `pod-security.kubernetes.io/enforce: privileged` label.

### Runners Not Registering with GitHub

**Symptom**: Runners not appearing in GitHub organization settings.

**Check**:
1. Listener logs: `kubectl logs -n arc-runners -l app.kubernetes.io/component=listener`
2. Verify GitHub App credentials are correct
3. Ensure installation ID is for the correct organization

## Verification Commands

```bash
# Check runner pods
kubectl --context fzymgc-house get pods -n arc-runners

# Check runner logs
kubectl --context fzymgc-house logs -n arc-runners -l app.kubernetes.io/component=runner

# Check listener logs
kubectl --context fzymgc-house logs -n arc-runners -l app.kubernetes.io/component=listener

# Check ExternalSecret status
kubectl --context fzymgc-house describe externalsecret github-token -n arc-runners

# Check AutoscalingRunnerSet
kubectl --context fzymgc-house get autoscalingrunnerset -n arc-runners

# View runner in GitHub
# https://github.com/organizations/fzymgc-house/settings/actions/runners
```

## Related Documentation

- [GitHub ARC Documentation](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller)
- [ARC Helm Chart Values](https://github.com/actions/actions-runner-controller/blob/master/charts/gha-runner-scale-set/values.yaml)
