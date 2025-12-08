# Windmill ArgoCD Application Setup

This document summarizes the Windmill application setup created for the selfhosted cluster.

## Files Created

### Application Configuration (`argocd/app-configs/windmill/`)

1. **`namespace.yaml`** - Creates the windmill namespace
2. **`secrets.yaml`** - External secrets configuration for:
   - Database connection string
   - PostgreSQL user credentials
   - Windmill admin password
   - OIDC client credentials
3. **`certificate.yaml`** - TLS certificate from Vault issuer for windmill.fzymgc.house
4. **`ingress.yaml`** - Traefik IngressRoute with authentication middleware
5. **`db-windmill.yaml`** - PostgreSQL database and user configuration for CNPG
6. **`kustomization.yaml`** - Kustomize configuration organizing all resources
7. **`README.md`** - Comprehensive documentation

### Cluster Application

8. **`argocd/cluster-app/templates/windmill.yaml`** - ArgoCD Application definition

### Modified Files

9. **`argocd/app-configs/cnpg/postgres-cluster.yaml`** - Added windmill database user
10. **`argocd/app-configs/cnpg/kustomization.yaml`** - Added windmill database reference

## Key Features

### Helm Chart Integration
- Uses official Windmill Helm chart from `windmill-labs/windmill-helm-charts`
- Version: `2.0.470` (latest as of September 8, 2025)
- Configured with external PostgreSQL, disabling built-in database

### Security & Authentication
- TLS certificates from internal Vault CA
- External secrets management via Vault
- OIDC integration ready (Authentik client configuration needed)
- Traefik authentication middleware for additional security

### High Availability & Scalability
- 2 app replicas for high availability
- 3 worker replicas for job processing
- 1 LSP replica for language server functionality
- Resource limits and requests configured (estimated values, should be tuned based on actual usage)

### Database Integration
- Dedicated PostgreSQL database in existing CNPG cluster
- Managed database user with proper permissions
- TLS-enabled database connections

### Monitoring & Operations
- Reloader annotations for automatic config reload
- Proper resource limits for monitoring
- Health checks via Helm chart configuration

## Deployment

The application follows the established GitOps patterns:
- Sync wave: `1` (deploys after core infrastructure)
- Project: `core-services`
- Automated sync with prune and self-heal enabled
- Respects ignore differences for External Secrets

## Required Vault Configuration

Before deployment, configure these secrets in Vault:

```bash
# Database credentials
vault kv put fzymgc-house/cluster/postgres/users/main-windmill \
  username=windmill \
  password=<secure-password>

# Application secrets
vault kv put fzymgc-house/cluster/windmill \
  admin_password=<admin-password> \
  oidc_client_id=<authentik-client-id> \
  oidc_client_secret=<authentik-client-secret>
```

## Access URLs

- Primary: `https://windmill.fzymgc.house`
- Alternative: `https://windmill.k8s.fzymgc.house`

## Next Steps

1. Configure the required Vault secrets
2. Set up Authentik OIDC client for Windmill
3. Commit and push changes to trigger ArgoCD sync
4. Verify deployment and access

The setup follows all established patterns in the repository and integrates seamlessly with the existing infrastructure stack.
