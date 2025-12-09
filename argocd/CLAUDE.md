# CLAUDE.md - ArgoCD Directory

This file provides guidance to Claude Code when working with ArgoCD application configurations.

## Directory Structure

```
argocd/
├── app-configs/         # Application-specific configurations
│   ├── monitoring-*     # Monitoring stack components
│   ├── windmill/        # Windmill workflow automation
│   ├── arc-runners/     # GitHub Actions Runner Controller
│   └── ...
└── cluster-app/         # Cluster-wide application definitions
```

## Application Configuration Patterns

Each application directory should contain:
- `kustomization.yaml` - Kustomize configuration
- Application-specific YAML manifests
- External secrets configurations

### Standard Kustomization
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - service-account.yaml
  - external-secrets.yaml
  - application-manifests.yaml
```

## Naming Conventions

- Use kebab-case for resource names: `grafana-config`, `monitoring-prometheus`
- Namespace names should match application purpose
- Service accounts should be descriptive: `grafana-dashboard-updater`

## External Secrets Integration

### Standard ExternalSecret Pattern
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-secrets
  namespace: app-namespace
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: app-secrets
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: secret/fzymgc-house/app
        property: password
```

## Security Best Practices

### Service Account Configuration
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: app-namespace
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "app-role"
automountServiceAccountToken: false  # Only mount when needed
```

### RBAC Configuration
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: app-namespace
  name: app-role
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "create", "update", "patch"]
    resourceNames: ["specific-configmap"]  # Be specific when possible
```

## Common Commands

```bash
# Apply specific application config
kubectl --context fzymgc-house apply -k argocd/app-configs/grafana-config

# Validate before applying
kubectl --context fzymgc-house apply --dry-run=client -k argocd/app-configs/app-name

# Check application status
kubectl --context fzymgc-house get all -n app-namespace

# View kustomize output
kubectl --context fzymgc-house kustomize argocd/app-configs/app-name
```

## Troubleshooting

### Kustomization Issues
```bash
# Test kustomization locally
kubectl kustomize argocd/app-configs/app-name

# Validate YAML syntax
yamllint argocd/app-configs/app-name/*.yaml

# Check for missing resources
kubectl --context fzymgc-house apply --dry-run=client -k argocd/app-configs/app-name
```

### External Secrets Issues
```bash
# Check ExternalSecret status
kubectl --context fzymgc-house describe externalsecret -n app-namespace

# Verify ClusterSecretStore
kubectl --context fzymgc-house get clustersecretstore

# Check Vault connectivity
kubectl --context fzymgc-house logs -n external-secrets deployment/external-secrets
```

## GitOps Workflow Integration

Terraform GitOps automation has been migrated to Windmill:
- Windmill flows in `windmill/` directory handle Terraform plan/apply
- GitHub Actions trigger Windmill deployments on PR merge
- Discord notifications for approvals and status updates

See `docs/windmill-migration.md` for details.

## Best Practices

1. **Namespace Isolation**: Each application in its own namespace
2. **Resource Limits**: Set appropriate resource requests/limits
3. **Health Checks**: Include readiness and liveness probes
4. **Monitoring**: Add appropriate labels for Prometheus scraping
5. **Documentation**: Include comments explaining non-obvious configurations
