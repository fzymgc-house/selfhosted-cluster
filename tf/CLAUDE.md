# CLAUDE.md - Terraform Directory

Guidance for Claude Code when working with Terraform code in this directory.

**See also:**
- `../CLAUDE.md` - Repository overview, workflow, MCP/skill guidance
- `../argocd/CLAUDE.md` - ExternalSecrets that consume Vault policies defined here

## Module Structure

Each Terraform module **MUST** include these files:
- `versions.tf` - Provider version constraints
- `terraform.tf` - Provider configurations
- `variables.tf` - Input variables
- `outputs.tf` - Output values
- `main.tf` - Main resource definitions

Additional files for specific modules:
- `vault.tf` - Vault-specific resources
- `policy-*.tf` - Grouped policy definitions
- `k8s-*.tf` - Kubernetes-specific resources

## File Naming Patterns

Group related resources logically:
```
policy-cert-manager.tf      # Cert-manager specific policies
policy-external-secrets.tf   # External secrets policies
k8s-cert-manager.tf         # Kubernetes auth for cert-manager
entities.tf                 # Entity definitions
groups-and-roles.tf         # Group and role assignments
```

## Resource Naming

**MUST** use underscore_separated names:
```hcl
# Correct
resource "vault_policy" "cert_manager_issuer" { }
resource "vault_kubernetes_auth_backend_role" "external_secrets_operator" { }

# Wrong - MUST NOT use hyphens or abbreviations
resource "vault_policy" "cert-manager-issuer" { }
resource "vault_policy" "cm" { }
```

## Provider Configuration

### versions.tf Template

**Note:** Provider versions vary by module. Check each module's `versions.tf` for exact versions.

```hcl
terraform {
  required_version = ">= 1.12.2"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"  # Exact version varies by module
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"  # Exact version varies by module
    }
  }
}
```

### terraform.tf Template
```hcl
provider "vault" {
  address = "https://vault.fzymgc.house"
  # Auth via VAULT_TOKEN environment variable
}

provider "kubernetes" {
  config_path    = "~/.kube/configs/fzymgc-house-admin.yml"
  config_context = "fzymgc-house"
}
```

## Variable Patterns

### variables.tf
```hcl
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

variable "vault_token" {
  description = "Vault authentication token"
  type        = string
  sensitive   = true
}
```

## Vault-Specific Patterns

### Policy Definition
```hcl
data "vault_policy_document" "cert_manager" {
  rule {
    path         = "pki_int/sign/fzymgc-house"
    capabilities = ["create", "update"]
    description  = "Allow cert-manager to sign certificates"
  }
}

resource "vault_policy" "cert_manager" {
  name   = "cert-manager"
  policy = data.vault_policy_document.cert_manager.hcl
}
```

### Kubernetes Auth Backend
```hcl
resource "vault_kubernetes_auth_backend_role" "app_name" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "app-name"
  bound_service_account_names      = ["app-sa"]
  bound_service_account_namespaces = ["app-namespace"]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.app_name.name]
}
```

## Common Commands

```bash
# Initialize module
terraform init

# Format check
terraform fmt -check -recursive

# Validate configuration
terraform validate

# Plan changes
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan

# Show current state
terraform show

# Import existing resources
terraform import vault_policy.example policy-name
```

## Best Practices

### State Management
- Use remote state with encryption
- Never commit state files to Git
- Use state locking when available

### Resource Dependencies
```hcl
resource "vault_mount" "pki" {
  path = "pki"
  type = "pki"
}

resource "vault_pki_secret_backend_role" "example" {
  backend = vault_mount.pki.path  # Explicit dependency
  name    = "example-role"
  # ... other configuration
}
```

### Dynamic Blocks
```hcl
resource "vault_policy" "dynamic_example" {
  name = "dynamic-policy"

  policy = jsonencode({
    path = {
      for path in var.secret_paths : path => {
        capabilities = ["read", "list"]
      }
    }
  })
}
```

### For Each Loops
```hcl
resource "vault_generic_secret" "app_secrets" {
  for_each = var.applications

  path = "secret/data/${each.key}"
  data_json = jsonencode({
    username = each.value.username
    password = each.value.password
  })
}
```

## Security

### Sensitive Variables

- **MUST** mark password/token variables with `sensitive = true`
- **MUST NOT** expose secrets in outputs or logs
- **SHOULD** use Vault data sources instead of variable inputs where possible

```hcl
variable "database_password" {
  description = "Database password"
  type        = string
  sensitive   = true  # REQUIRED - prevents log exposure
}

output "connection_string" {
  value     = "postgresql://user:${var.database_password}@host/db"
  sensitive = true  # REQUIRED for secrets
}
```

### Using Vault for Secrets
```hcl
# Read secrets from Vault
data "vault_generic_secret" "database" {
  path = "secret/database/config"
}

# Use in resources
resource "kubernetes_secret" "database" {
  metadata {
    name      = "database-config"
    namespace = "app"
  }

  data = {
    password = data.vault_generic_secret.database.data["password"]
  }
}
```

## Module-Specific Guidance

### Cluster Bootstrap (`tf/cluster-bootstrap`)
- Deploys core infrastructure: cert-manager, External Secrets, Longhorn, MetalLB, ArgoCD
- Run after Ansible deploys k3s
- Single apply for full infrastructure bootstrap

### Vault Module (`tf/vault`)
- Define all policies in separate `policy-*.tf` files
- Group related Kubernetes auth roles in `k8s-*.tf` files
- Use descriptive policy names matching their purpose
- Document each policy's intended use

### Authentik Module (`tf/authentik`)
- Configure OIDC applications systematically
- Use consistent naming for applications
- Group related configurations

### Grafana Module (`tf/grafana`)
- Manage dashboards as code
- Configure data sources programmatically
- Set up proper folder structure

### Cloudflare Module (`tf/cloudflare`)
- DNS record management
- Cloudflare Tunnel configuration

### Core Services (`tf/core-services`)
- Cross-cutting service configurations
