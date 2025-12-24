# CLAUDE.md - ArgoCD Directory

Guidance for Claude Code when working with ArgoCD application configurations.

**See also:**
- `../CLAUDE.md` - Repository overview, workflow, MCP/skill guidance
- `../tf/CLAUDE.md` - Vault policies and Kubernetes auth roles for ExternalSecrets

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

Each application directory **MUST** contain:
- `kustomization.yaml` - Kustomize configuration
- Application-specific YAML manifests

Each application directory **SHOULD** contain:
- `*-secrets.yaml` - ExternalSecret definitions (if secrets needed)

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

- **MUST** use kebab-case for resource names: `grafana-config`, `monitoring-prometheus`
- **SHOULD** match namespace names to application purpose
- **SHOULD** use descriptive service account names: `grafana-dashboard-updater`

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

## Security

### Service Accounts

- **SHOULD** set `automountServiceAccountToken: false` unless token needed
- **MUST** match service account name to Vault Kubernetes auth role

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: app-namespace
automountServiceAccountToken: false
```

**Note:** Secrets are injected via ExternalSecrets Operator (not Vault agent).

### RBAC

- **MUST** scope Roles to specific namespaces (not ClusterRoles unless required)
- **SHOULD** use `resourceNames` to limit access to specific resources

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
    resourceNames: ["specific-configmap"]  # Scope access
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

1. **MUST** isolate each application in its own namespace
2. **SHOULD** set appropriate resource requests/limits
3. **SHOULD** include readiness and liveness probes
4. **SHOULD** add labels for Prometheus scraping where applicable
5. **SHOULD** include comments explaining non-obvious configurations
