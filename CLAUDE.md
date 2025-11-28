# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Self-hosted Kubernetes cluster using k3s on TuringPi 2 hardware with RK1 and Jetson Orin NX compute modules. Infrastructure is managed via Ansible for cluster deployment, Terraform for external service configuration, and Kubernetes manifests for application deployment.

**Key Technologies:**
- Kubernetes (k3s) with Calico CNI
- HashiCorp Vault for secrets management
- Authentik for SSO/identity
- Grafana + VictoriaMetrics for observability
- Terraform for infrastructure as code
- Ansible for cluster automation

## Development Environment Setup

### Python Virtual Environment (Required)

This repository uses a Python virtual environment for Ansible and dependencies:

```bash
# One-time setup
./setup-venv.sh

# Activate before any Ansible work
source .venv/bin/activate

# When done
deactivate
```

The `.envrc` file (if using direnv) contains environment variables for BMC access and SOPS encryption keys.

### Required Tools

- Python 3.13+ (see `.python-version`)
- kubectl configured with `fzymgc-house` context
- 1Password CLI (for secrets management)
- Terraform (for infrastructure changes)
- direnv (optional, for automatic environment activation)

## Development Workflow

**CRITICAL: This repository follows a strict GitOps workflow. ALL changes must go through proper feature branches and pull requests.**

### Branch and PR Workflow

1. **NEVER commit directly to `main`**
   - All changes must be made on feature branches
   - Branch naming: `feat/description`, `fix/description`, `chore/description`
   - Example: `feat/add-monitoring`, `fix/database-connection`

2. **Feature Branch Process**
   ```bash
   # Create a new branch from main
   git checkout main
   git pull
   git checkout -b feat/your-feature-name

   # Make your changes, commit, and push
   git add .
   git commit -m "feat: Description of changes"
   git push -u origin feat/your-feature-name

   # Create a pull request using gh CLI
   gh pr create --title "feat: Description" --body "PR description"
   ```

3. **Pull Request Requirements**
   - All PRs must pass automated checks (validation, linting, reviews)
   - PRs are merged to `main` after approval
   - Use meaningful commit messages following conventional commits format

### GitOps Principles

**CRITICAL: Do NOT apply changes directly to the running cluster using `kubectl apply`**

This cluster uses ArgoCD for GitOps-based deployment. Changes are deployed as follows:

1. **Source of Truth**: Git repository (`main` branch) is the single source of truth
2. **Automated Sync**: ArgoCD automatically syncs changes from Git to the cluster
3. **No Manual Application**: Never use `kubectl apply` to deploy application changes
4. **Exception**: Debugging only - temporary `kubectl` commands for troubleshooting are acceptable, but must not be permanent changes

**Correct Workflow:**
```bash
# 1. Make changes in a feature branch
git checkout -b feat/update-deployment
# Edit deployment.yaml
git add argocd/app-configs/app-name/deployment.yaml
git commit -m "feat: Update deployment configuration"
git push -u origin feat/update-deployment

# 2. Create PR and merge after review
gh pr create --title "feat: Update deployment"

# 3. ArgoCD automatically syncs changes after merge to main
# No manual kubectl apply needed!
```

**Incorrect Workflow (DO NOT DO THIS):**
```bash
# ❌ WRONG - Do not apply directly to cluster
kubectl --context fzymgc-house apply -f deployment.yaml

# ❌ WRONG - Do not commit directly to main
git checkout main
git commit -m "changes"
git push origin main
```

### Monitoring Changes

After merging a PR, monitor ArgoCD sync:
```bash
# Check application sync status
kubectl --context fzymgc-house get application app-name -n argocd

# Watch application health
kubectl --context fzymgc-house get application app-name -n argocd -w
```

## Common Commands

### Ansible Operations

Always activate the virtual environment first: `source .venv/bin/activate`

```bash
# Deploy/update k3s cluster
ansible-playbook -i ansible/inventory/hosts.yml ansible/k3s-playbook.yml

# Bootstrap nodes (OS configuration)
ansible-playbook -i ansible/inventory/hosts.yml ansible/bootstrap-nodes-playbook.yml

# Reboot cluster nodes
ansible-playbook -i ansible/inventory/hosts.yml ansible/reboot-nodes-playbook.yml

# Run specific tags (e.g., update Longhorn only)
ansible-playbook -i ansible/inventory/hosts.yml ansible/k3s-playbook.yml --tags k8s-longhorn

# Syntax check and dry run
ansible-playbook -i ansible/inventory/hosts.yml playbook.yml --syntax-check
ansible-playbook -i ansible/inventory/hosts.yml playbook.yml --check --diff
```

### Kubernetes Operations

Always use the `fzymgc-house` context:

```bash
# View cluster status
kubectl --context fzymgc-house get nodes
kubectl --context fzymgc-house get pods -A

# Apply application configurations
kubectl --context fzymgc-house apply -k argocd/app-configs/app-name

# Validate before applying
kubectl --context fzymgc-house apply --dry-run=client -k argocd/app-configs/app-name

# View kustomize output
kubectl --context fzymgc-house kustomize argocd/app-configs/app-name

# Check application logs
kubectl --context fzymgc-house logs -n namespace -l app=app-name
```

### Terraform Operations

Each Terraform module is independent. Work within the module directory:

```bash
# Navigate to specific module
cd tf/vault  # or tf/authentik, tf/grafana, tf/core-services

# Initialize and plan
terraform init
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan

# Format and validate
terraform fmt -check -recursive
terraform validate
```

## Architecture Patterns

### Multi-Layer Infrastructure

The repository is organized in three layers:

1. **Ansible Layer** (`ansible/`): Physical cluster deployment
   - Node bootstrapping and OS configuration
   - k3s cluster deployment via k3sup
   - Core infrastructure installation
   - Hardware-level automation (BMC access, network config)

2. **Terraform Layer** (`tf/`): External service configuration
   - Vault policies, auth backends, PKI
   - Authentik OIDC applications and groups
   - Grafana dashboards and data sources
   - Services that have Terraform providers

3. **Kubernetes Layer** (`argocd/`): Application deployment
   - Application manifests and kustomizations
   - ExternalSecrets for Vault integration
   - Argo Workflows for GitOps automation
   - Service-specific configurations

### Secrets Management Flow

Secrets flow from Vault → Kubernetes via ExternalSecrets Operator:

1. Secrets are stored in HashiCorp Vault at paths like `secret/fzymgc-house/app`
2. Vault policies (defined in `tf/vault/policy-*.tf`) control access
3. Kubernetes auth backend roles map service accounts to policies
4. ExternalSecret resources sync Vault secrets to Kubernetes secrets
5. Applications consume secrets as environment variables or mounted files

### GitOps Automation

Many infrastructure components use Argo Events + Argo Workflows for GitOps:

- GitHub webhook triggers workflows on push/PR
- Workflows run Terraform plan/apply for infrastructure changes
- Service accounts have limited RBAC scopes for safety
- Workflows defined in `argocd/app-configs/*/workflow-template-wf.yaml`

## File Organization Principles

### Terraform Modules

Each module follows this structure:
- `versions.tf`: Provider version constraints
- `terraform.tf`: Provider configurations
- `variables.tf`: Input variables
- `outputs.tf`: Output values
- `main.tf`: Main resource definitions
- `policy-*.tf`: Grouped Vault policies (vault module)
- `k8s-*.tf`: Kubernetes auth configurations (vault module)

### Ansible Roles

Located in `ansible/roles/`:
- `k3sup/`: k3s cluster deployment and management
- `tp2-bootstrap-node/`: Node preparation and configuration

Roles include standard structure: `tasks/`, `templates/`, `files/`, `handlers/`, `defaults/`, `vars/`

### ArgoCD Application Configs

Located in `argocd/app-configs/[app-name]/`:
- `kustomization.yaml`: Kustomize configuration
- `namespace.yaml`: Namespace definition
- `rbac.yaml`: RBAC resources (roles, bindings, service accounts)
- Application-specific manifests
- `*-secrets.yaml`: ExternalSecret definitions
- `workflow-template-wf.yaml`: Argo Workflow for GitOps (if applicable)

## Domain and Service Access

All services use `*.fzymgc.house` domain with automatic TLS via cert-manager:

- Vault: `https://vault.fzymgc.house`
- Authentik: `https://auth.fzymgc.house`
- Grafana: `https://grafana.fzymgc.house`
- Traefik Dashboard: `https://traefik.fzymgc.house`

Ingress is managed by Traefik with IngressRoute CRDs.

## Critical Configuration Details

### Network Configuration

- **Cluster CIDR**: `10.42.0.0/16` (pods)
- **Service CIDR**: `10.43.0.0/16` (services)
- **MetalLB Pool**: `10.255.254.6` (LoadBalancer IPs)
- **CNI**: Calico (installed by k3s)

### Storage Classes

- **Longhorn**: Default distributed storage (`longhorn` StorageClass)
- **PostgreSQL**: Special StorageClass with database optimizations
- Configured in `argocd/app-configs/shared-resources/longhorn-storage-classes.yaml`

### Certificate Management

- **Let's Encrypt**: Cloudflare DNS-01 challenge for public certificates
- **Vault PKI**: Internal certificate authority for cluster certificates
- **cert-manager**: Automated certificate lifecycle

## Context-Specific Instructions

### Ansible Development

See `ansible/CLAUDE.md` for detailed Ansible conventions including:
- Always use FQCN (Fully Qualified Collection Names)
- File headers with license and language annotations
- Variable naming conventions (snake_case, role prefixes)
- Common task patterns and idempotency practices

### Terraform Development

See `tf/CLAUDE.md` for Terraform-specific guidance including:
- Module structure requirements
- Resource naming conventions (underscore_separated)
- Vault policy patterns
- Security best practices for sensitive variables

### ArgoCD/Kubernetes Development

See `argocd/CLAUDE.md` for Kubernetes manifest guidance including:
- ExternalSecret patterns
- Service account and RBAC configurations
- Argo Workflow template structure
- Kustomization best practices

## Testing and Validation

### Before Committing

1. **Ansible**: Syntax check and dry run with `--check --diff`
2. **Terraform**: `terraform fmt -check`, `terraform validate`, `terraform plan`
3. **Kubernetes**: `kubectl apply --dry-run=client` or `kubectl kustomize`
4. **YAML Linting**: Use `yamllint` for YAML files

### Common Debugging Steps

1. Check resource status: `kubectl --context fzymgc-house get [resource] -n [namespace]`
2. View logs: `kubectl --context fzymgc-house logs -n [namespace] [pod]`
3. Describe resource: `kubectl --context fzymgc-house describe [resource] -n [namespace]`
4. Check ExternalSecret sync: `kubectl --context fzymgc-house describe externalsecret -n [namespace]`
5. Verify Vault connectivity: `kubectl --context fzymgc-house logs -n external-secrets deployment/external-secrets`

## Hardware-Specific Considerations

### TuringPi 2 Architecture

- Two TPI hosts (alpha/beta) each managing multiple compute modules
- BMC credentials stored in `.envrc` (not committed to Git)
- Nodes use Armbian 25.08 with systemd-networkd for networking
- Mix of RK1 (general compute) and Jetson Orin NX (AI/ML) modules

### Node Groups

Defined in `ansible/inventory/`:
- `tp_cluster_nodes`: All cluster nodes
- `rk1_nodes`: RK1 compute modules
- `jetson_nodes`: Jetson Orin NX modules (if configured separately)

## Security Considerations

- Never commit secrets to Git (use Vault or SOPS-encrypted files)
- Service accounts follow principle of least privilege
- All external services use HTTPS with valid certificates
- Vault policies are granular and scoped to specific paths
- RBAC is namespace-scoped where possible
