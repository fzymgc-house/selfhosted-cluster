# Cluster Bootstrap Terraform Module

This Terraform module bootstraps the core infrastructure components for the fzymgc-house Kubernetes cluster.

## Components

The module installs and configures the following components in order:

1. **Prometheus Operator CRDs** - Custom Resource Definitions for Prometheus monitoring
2. **cert-manager** - Automated certificate management
3. **External Secrets Operator** - Syncs secrets from HashiCorp Vault to Kubernetes
4. **Longhorn** - Distributed block storage with encryption
5. **MetalLB** - Load balancer for bare metal Kubernetes
6. **ArgoCD** - GitOps continuous delivery

## Prerequisites

- Kubernetes cluster running (deployed via Ansible)
- `kubectl` configured with `fzymgc-house-admin.yml` kubeconfig
- HashiCorp Vault accessible at `https://vault.fzymgc.house`
- Valid `VAULT_TOKEN` with `infrastructure-developer` policy
- Terraform Cloud workspace configured with tags `main-cluster` and `bootstrap`

## Secrets Required in Vault

The following secrets must exist in Vault before running this module:

### Infrastructure PKI
- `fzymgc-house/infrastructure/pki/fzymgc-ica1-ca`
  - `cert` - ICA1 certificate
  - `cleartext_key` - ICA1 private key
  - `fullchain` - Full certificate chain

### Longhorn
- `fzymgc-house/cluster/longhorn/crypto-key`
  - `password` - Encryption key for volumes
- `fzymgc-house/cluster/longhorn/cloudflare-r2`
  - `username` - R2 access key ID
  - `password` - R2 secret access key

### ArgoCD
- `fzymgc-house/cluster/argocd`
  - `authentik_client_id` - Authentik OIDC client ID
  - `authentik_client_secret` - Authentik OIDC client secret
  - `github_app_private_key` - GitHub App private key (base64 encoded)
  - `admin.password` - ArgoCD admin password
  - `admin.password_mtime` - Password modification time
  - `server.secretkey` - ArgoCD server secret key
  - `webhook.github.secret` - GitHub webhook secret

## Usage

```bash
# Navigate to module directory
cd tf/cluster-bootstrap

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

## Workflow

1. **Deploy Kubernetes cluster** using Ansible playbook:
   ```bash
   ansible-playbook -i ansible/inventory/hosts.yml ansible/k3s-playbook.yml
   ```

2. **Bootstrap cluster components** using this Terraform module:
   ```bash
   cd tf/cluster-bootstrap
   terraform init
   terraform apply
   ```

3. **GitOps takes over** - ArgoCD automatically deploys applications from the `argocd/cluster-app` directory

## Module Structure

```
tf/cluster-bootstrap/
├── README.md                  # This file
├── versions.tf                # Provider version constraints
├── terraform.tf               # Terraform Cloud backend configuration
├── variables.tf               # Input variables
├── outputs.tf                 # Output values
├── prometheus-crds.tf         # Prometheus Operator CRDs
├── cert-manager.tf            # cert-manager installation
├── external-secrets.tf        # External Secrets Operator
├── longhorn.tf                # Longhorn storage
├── metallb.tf                 # MetalLB load balancer
├── argocd.tf                  # ArgoCD GitOps
└── manifests/
    └── fzymgc-house-issuer.yaml  # ClusterIssuer manifest
```

## Dependency Graph

```
Prometheus CRDs
    ↓
cert-manager → External Secrets → Longhorn → MetalLB
    ↓              ↓                              ↓
    └──────────────┴──────────────────────────────┴→ ArgoCD
```

## Outputs

- `argocd_namespace` - ArgoCD namespace name
- `longhorn_namespace` - Longhorn namespace name
- `cert_manager_namespace` - cert-manager namespace name
- `external_secrets_namespace` - External Secrets namespace name
- `metallb_namespace` - MetalLB namespace name

## Notes

- This module uses Terraform Cloud for remote state storage
- All secrets are fetched from HashiCorp Vault, not stored in Terraform state
- The module is idempotent and can be safely re-run
- Helm v4 compatible (uses the Helm Terraform provider)
- Dependencies are explicitly defined to ensure correct installation order
