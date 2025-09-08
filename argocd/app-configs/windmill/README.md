# Windmill Configuration

This directory contains the ArgoCD application configuration for [Windmill](https://windmill.dev), a developer platform to turn scripts into workflows and UIs.

## Overview

Windmill is deployed using:
- **Helm Chart**: `windmill-labs/windmill-helm-charts`
- **Database**: PostgreSQL (using the existing CNPG cluster)
- **Authentication**: Integrated with Authentik OIDC
- **Ingress**: Traefik with TLS certificates from Vault
- **Secrets Management**: External Secrets Operator with Vault backend

## Components

### Core Files

- `namespace.yaml` - Creates the windmill namespace
- `secrets.yaml` - External secrets for database credentials and OIDC configuration
- `certificate.yaml` - TLS certificate from Vault issuer
- `ingress.yaml` - Traefik IngressRoute configuration
- `db-windmill.yaml` - PostgreSQL database and user configuration
- `kustomization.yaml` - Kustomize configuration

### Cluster App

- `../../cluster-app/templates/windmill.yaml` - ArgoCD Application definition

## Configuration

### Required Vault Secrets

The following secrets must be configured in Vault:

```bash
# Database user credentials
vault kv put fzymgc-house/cluster/postgres/users/main-windmill \
  username=windmill \
  password=<secure-password>

# Windmill application secrets
vault kv put fzymgc-house/cluster/windmill \
  admin_password=<admin-password> \
  oidc_client_id=<authentik-client-id> \
  oidc_client_secret=<authentik-client-secret>
```

### Helm Chart Configuration

The Windmill application is configured with:

- **App Replicas**: 2 (for high availability)
- **Worker Replicas**: 3 (for job processing)
- **LSP Replicas**: 1 (for language server)
- **Base URL**: `https://windmill.fzymgc.house`
- **Database**: External PostgreSQL (CNPG cluster)
- **Built-in components disabled**: PostgreSQL, Redis, MinIO (using external services)

### Resource Limits (Estimates)

**⚠️ Note**: These resource limits are estimates, not based on official Windmill recommendations. They should be adjusted based on actual usage patterns and performance monitoring.

- **App Pods**: 500Mi-2Gi memory, 200m-1000m CPU (Estimated 4x chart defaults for UI responsiveness)
- **Worker Pods**: 1Gi-4Gi memory, 500m-2000m CPU (Estimated higher for job processing workloads)
- **LSP Pods**: 200Mi-1Gi memory, 100m-500m CPU (Estimated conservative for language server functionality)

**Chart Defaults**: ~128-256Mi memory, 100-200m CPU per component

## Access

Once deployed, Windmill will be accessible at:
- Primary: `https://windmill.fzymgc.house`
- Alternative: `https://windmill.k8s.fzymgc.house`

## Database Integration

A dedicated PostgreSQL database and user are created in the existing CNPG cluster:
- Database: `windmill`
- User: `windmill` (managed by CNPG)
- Connection: TLS-enabled connection to the main PostgreSQL cluster

## Monitoring

The application includes:
- Reloader annotations for automatic restart on config changes
- Resource requests and limits for proper resource management
- Health checks and readiness probes (configured in Helm chart)

## Troubleshooting

### Common Issues

1. **Database Connection Issues**
   - Verify the windmill user exists in PostgreSQL
   - Check the database URL in the windmill-secrets secret
   - Ensure the windmill database is created

2. **OIDC Authentication Issues**
   - Verify Authentik client configuration
   - Check OIDC credentials in windmill-oidc-creds secret
   - Ensure callback URLs are configured in Authentik

3. **Ingress Issues**
   - Verify TLS certificate is issued correctly
   - Check Traefik IngressRoute configuration
   - Ensure DNS resolves to the correct IP

### Useful Commands

```bash
# Check application status
kubectl get pods -n windmill

# View application logs
kubectl logs -n windmill deployment/windmill-app

# Check secrets
kubectl get secrets -n windmill

# View database status
kubectl get database windmill -n postgres
```
