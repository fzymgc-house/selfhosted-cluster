# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a GitOps-managed Kubernetes cluster for home infrastructure using k3s, Terraform, and Ansible. The cluster runs on TuringPi 2 boards with RK1 and Jetson Orin NX compute modules.

**Important**: Each major directory (`ansible/`, `argocd/`, `tf/`) contains its own CLAUDE.md with specific conventions and patterns for that technology stack.

## Core Principles

- **GitOps First**: All infrastructure changes through Git, no manual cluster modifications
- **Security by Default**: Vault for secrets, mTLS, RBAC everywhere
- **High Availability**: 3+ replicas, anti-affinity rules
- **Observability**: Metrics, logs, and dashboards for everything
- **Automation**: Prefer automated over manual processes

## Key Architecture Decisions

- **Ansible for cluster bootstrap only**: Node provisioning, k3s installation, and core infrastructure components (Longhorn, cert-manager, etc.) deployed via Ansible. Ansible is NOT used for application deployment.
- **ArgoCD for application deployment**: All user applications and services managed by ArgoCD with GitOps automation
- **Terraform for external services**: Vault, Authentik, Grafana, and external integrations managed via Terraform
- **Vault-centric security**: All secrets managed through HashiCorp Vault with External Secrets Operator
- **1Password CLI**: Used for initial secrets bootstrapping and developer access

## Development Commands

### Cluster Management
```bash
# Bootstrap new nodes
ansible-playbook -i ansible/inventory/hosts.yml ansible/bootstrap-nodes-playbook.yml

# Deploy/update k3s cluster
ansible-playbook -i ansible/inventory/hosts.yml ansible/k3s-playbook.yml

# Reboot cluster nodes (rolling)
ansible-playbook -i ansible/inventory/hosts.yml ansible/reboot-nodes-playbook.yml

# Deploy specific component with tags
ansible-playbook -i ansible/inventory/hosts.yml ansible/k3s-playbook.yml --tags k8s-longhorn

# Dry run to preview changes
ansible-playbook -i ansible/inventory/hosts.yml ansible/k3s-playbook.yml --check --diff
```

### Available Ansible Tags
Common tags for cluster infrastructure (NOT applications):
- `k3s` - Core k3s cluster installation
- `k8s-longhorn` - Longhorn distributed storage
- `k8s-cert-manager` - Certificate management
- `k8s-external-secrets` - External Secrets Operator
- `k8s-metallb` - MetalLB load balancer
- `k8s-calico` - Calico CNI
- `k8s-traefik` - Traefik ingress controller
- `k8s-vault` - HashiCorp Vault

**Note**: These tags deploy infrastructure components only. Applications are managed by ArgoCD.

### Terraform Operations
```bash
# Work with Vault configuration
cd tf/vault
terraform init
terraform plan
terraform apply

# Work with Authentik
cd tf/authentik
terraform init
terraform plan
terraform apply

# Work with Grafana
cd tf/grafana
terraform init
terraform plan
terraform apply

# Always validate before applying
terraform fmt -check
terraform validate
```

### ArgoCD Operations
```bash
# Use the fzymgc-house context for all kubectl commands
kubectl --context fzymgc-house get nodes
kubectl --context fzymgc-house get pods -A

# Check ArgoCD application status
kubectl --context fzymgc-house get applications -n argocd

# Sync an application
kubectl --context fzymgc-house -n argocd patch application <app-name> -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"normal"}}}' --type=merge

# View application details
kubectl --context fzymgc-house describe application <app-name> -n argocd

# For testing/validation only (ArgoCD normally handles deployment):
kubectl --context fzymgc-house apply --dry-run=client -k argocd/app-configs/<app-name>
kubectl --context fzymgc-house kustomize argocd/app-configs/<app-name>
```

### Secrets Management with 1Password CLI
```bash
# Read secret from 1Password
op read "op://vault-name/item-name/field-name"

# Use in scripts
export VAULT_TOKEN=$(op read "op://Homelab/Vault/root-token")

# Inject into ansible-playbook
ansible-playbook -e "vault_token=$(op read 'op://Homelab/Vault/token')" playbook.yml
```

### Testing and Validation
```bash
# Test Ansible playbooks
ansible-playbook -i ansible/inventory/hosts.yml <playbook>.yml --check

# Validate Kubernetes YAML
kubectl --context fzymgc-house apply --dry-run=client -f <manifest>.yaml

# Terraform validation
cd tf/<module>
terraform fmt -check
terraform validate
terraform plan
```

## Project Structure

### `/ansible` - Cluster Bootstrap Only
- `inventory/hosts.yml`: Node definitions and groups
- `roles/k3sup/`: Main k3s deployment role with task-based organization
- `roles/tp2-bootstrap-node/`: Node preparation and configuration
- Playbooks use tags for selective deployment of infrastructure components only
- **Scope**: Node management, k3s cluster, and core infrastructure (storage, networking, cert-manager, vault)
- **Not used for**: Application deployment (handled by ArgoCD)
- See `ansible/CLAUDE.md` for Ansible-specific conventions

### `/tf` - External Service Configuration
Each module follows standard structure:
- `versions.tf`: Provider version constraints
- `terraform.tf`: Provider configurations
- `variables.tf`: Input variables
- `outputs.tf`: Output values
- `main.tf`: Main resource definitions
- Module-specific files like `policy-*.tf` for Vault policies
- See `tf/CLAUDE.md` for Terraform-specific patterns

### `/argocd/app-configs` - ArgoCD Application Definitions
Each application has:
- `kustomization.yaml`: Kustomize configuration
- Application-specific YAML manifests
- External secrets configurations
- Workflow templates for GitOps automation
- See `argocd/CLAUDE.md` for Kubernetes manifest conventions

**ArgoCD manages these applications**: Changes merged to main branch are automatically synced by ArgoCD to the cluster. Manual `kubectl apply` should only be used for testing/validation.

## Important Conventions

### Ansible Best Practices
- Use Fully Qualified Collection Names (FQCN): `ansible.builtin.apt` not `apt`
- Variables use snake_case: `k3sup_version`
- Role variables prefixed with role name
- Tasks organized with tags for selective execution
- Always include file headers with SPDX license and language annotation

### Terraform Patterns
- Resource names use underscore_separated format
- Vault policies grouped by function: `policy-cert-manager.tf`
- Provider configurations in `terraform.tf`
- Version constraints in `versions.tf`
- All modules follow standard file structure

### Kubernetes Naming
- Resources use kebab-case: `cert-manager`, `external-secrets`
- Namespaces follow application names
- Labels include `app`, `app.kubernetes.io/name`, `app.kubernetes.io/instance`
- Service accounts should be descriptive and specific

## Security Considerations

- **Never commit secrets**: All secrets through Vault or SOPS encryption
- **Use External Secrets Operator**: For Kubernetes secret injection from Vault
- **mTLS by default**: Service-to-service communication encrypted
- **RBAC everywhere**: Principle of least privilege
- **Network policies**: Micro-segmentation between namespaces
- **Service accounts**: Set `automountServiceAccountToken: false` when not needed

## Cluster Access

- **Cluster context**: Always use `--context fzymgc-house`
- **Load balancer IP**: `10.255.254.6` (MetalLB)
- **Cluster DNS**: `10.43.0.10`
- **Pod CIDR**: `10.42.0.0/16`
- **Service CIDR**: `10.43.0.0/16`
- **Domain**: `*.fzymgc.house` (external services)

## Troubleshooting Quick Reference

### Pod Issues
```bash
# Check pod status
kubectl --context fzymgc-house get pods -A | grep -v "Running\|Completed"

# View pod logs
kubectl --context fzymgc-house logs -n namespace pod-name --previous

# Debug with ephemeral container
kubectl --context fzymgc-house debug pod-name -n namespace -it --image=busybox --share-processes
```

### Service Discovery
```bash
# Check endpoints
kubectl --context fzymgc-house get endpoints -n namespace

# Test DNS resolution
kubectl --context fzymgc-house run -it --rm debug --image=busybox --restart=Never -- nslookup service.namespace
```

### Vault Issues
```bash
# Check Vault status
kubectl --context fzymgc-house exec -n vault vault-0 -- vault status

# Test secret access
kubectl --context fzymgc-house exec -n vault vault-0 -- vault kv get secret/path

# Check Vault logs
kubectl --context fzymgc-house logs -n vault vault-0 -f
```

### External Secrets Not Syncing
```bash
# Check ExternalSecret status
kubectl --context fzymgc-house describe externalsecret secret-name -n namespace

# Check operator logs
kubectl --context fzymgc-house logs -n external-secrets deployment/external-secrets -f

# Verify ClusterSecretStore
kubectl --context fzymgc-house get clustersecretstore vault-backend -o yaml
```

### Ansible Playbook Failures
```bash
# Run with increased verbosity
ansible-playbook -i ansible/inventory/hosts.yml playbook.yml -vvv

# Check connectivity to nodes
ansible -i ansible/inventory/hosts.yml all -m ping

# Limit to single host for debugging
ansible-playbook -i ansible/inventory/hosts.yml playbook.yml --limit hostname -vvv
```

## Deployment Workflow

1. **Make changes**: Edit manifests, playbooks, or Terraform configs in feature branch
2. **Test locally**: Use `--check`, `--dry-run`, or `terraform plan` to validate
3. **Create PR**: Submit for review with clear description
4. **Review**: Automated checks and peer review
5. **Merge**: Merge to main branch
6. **Deploy**: 
   - **Ansible changes** (cluster/nodes): Run playbook with appropriate tags
   - **Terraform changes** (external services): `terraform apply` in relevant module
   - **Application changes** (argocd/app-configs): ArgoCD automatically syncs from Git (no manual action needed)

### Deployment Boundaries
- **Ansible**: Cluster nodes, k3s, core infrastructure (Longhorn, cert-manager, MetalLB, Traefik, Vault, External Secrets)
- **ArgoCD**: All user applications and services (Grafana dashboards, monitoring, databases, workloads)
- **Terraform**: External integrations (Vault policies, Authentik apps, Grafana data sources)

## Hardware Context

- **1x TuringPi 2** cluster board (hosts: alpha/beta)
- **4x RK1** compute modules (ARM64, 32GB RAM each)
- **4x Jetson Orin NX** compute modules (ARM64, AI/ML workloads)
- **OS**: Armbian 25.08 (Ubuntu Noble) with systemd-networkd
- **Network**: Private network with MetalLB for load balancing

## Security Checklist

When making changes, ensure:
- [ ] All secrets in Vault or encrypted with SOPS
- [ ] TLS enabled for all services
- [ ] Network policies implemented
- [ ] RBAC with least privilege
- [ ] Pod security standards enforced
- [ ] Security contexts configured
- [ ] No hardcoded credentials
- [ ] Service accounts use `automountServiceAccountToken: false` when not needed
- [ ] Resource limits and requests defined
