# HCP Terraform Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate Terraform execution from Windmill to HCP Terraform self-hosted agents with VCS-driven workflow and Vault OIDC dynamic credentials.

**Architecture:** Deploy HCP TF Operator in Kubernetes, create `tf/hcp-terraform` module to manage workspaces, add Vault OIDC auth for dynamic credentials, and deploy Cloudflare Worker for Discord notifications.

**Tech Stack:** Terraform (tfe provider), Kubernetes (HCP TF Operator), Vault (JWT auth), Cloudflare Workers

**Design Doc:** `docs/plans/2025-12-26-hcp-terraform-migration-design.md`

---

## Phase 1: HCP Terraform Module

Create the `tf/hcp-terraform` module that manages workspaces, agent pool, and notifications.

### Task 1.1: Create Module Structure

**Files:**
- Create: `tf/hcp-terraform/versions.tf`
- Create: `tf/hcp-terraform/terraform.tf`
- Create: `tf/hcp-terraform/variables.tf`

**Step 1: Create versions.tf**

```hcl
// versions.tf - Required versions for Terraform and providers

terraform {
  required_version = ">= 1.12.0"

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.62"
    }
  }
}
```

**Step 2: Create terraform.tf**

```hcl
// terraform.tf - Provider and backend configuration

terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      tags = ["main-cluster", "hcp-terraform"]
    }
  }
}

provider "tfe" {
  # Uses TFE_TOKEN environment variable
}
```

**Step 3: Create variables.tf**

```hcl
// variables.tf - Input variables

variable "organization" {
  description = "HCP Terraform organization name"
  type        = string
  default     = "fzymgc-house"
}

variable "github_repo" {
  description = "GitHub repository identifier"
  type        = string
  default     = "fzymgc-house/selfhosted-cluster"
}

variable "discord_webhook_url" {
  description = "Cloudflare Worker URL for Discord notifications"
  type        = string
  sensitive   = true
}
```

**Step 4: Validate module structure**

Run: `cd /workspaces/selfhosted-cluster/.worktrees/hcp-terraform-migration/tf/hcp-terraform && terraform fmt -check`
Expected: No formatting issues

**Step 5: Commit**

```bash
git add tf/hcp-terraform/
git commit -m "feat(hcp-terraform): add module structure with versions and variables"
```

---

### Task 1.2: Create Agent Pool Configuration

**Files:**
- Create: `tf/hcp-terraform/agent_pool.tf`
- Create: `tf/hcp-terraform/outputs.tf`

**Step 1: Create agent_pool.tf**

```hcl
// agent_pool.tf - Agent pool and token configuration

resource "tfe_agent_pool" "main" {
  name                = "fzymgc-house-k8s"
  organization        = var.organization
  organization_scoped = true
}

resource "tfe_agent_token" "k8s" {
  agent_pool_id = tfe_agent_pool.main.id
  description   = "Kubernetes cluster agent"
}
```

**Step 2: Create outputs.tf**

```hcl
// outputs.tf - Output values

output "agent_pool_id" {
  description = "Agent pool ID for workspace configuration"
  value       = tfe_agent_pool.main.id
}

output "agent_token" {
  description = "Agent token for Kubernetes deployment (store in Vault)"
  value       = tfe_agent_token.k8s.token
  sensitive   = true
}
```

**Step 3: Validate**

Run: `terraform fmt -check tf/hcp-terraform/`
Expected: No formatting issues

**Step 4: Commit**

```bash
git add tf/hcp-terraform/agent_pool.tf tf/hcp-terraform/outputs.tf
git commit -m "feat(hcp-terraform): add agent pool and token configuration"
```

---

### Task 1.3: Create Workspace Imports and Configuration

**Files:**
- Create: `tf/hcp-terraform/imports.tf`
- Create: `tf/hcp-terraform/workspaces.tf`
- Create: `tf/hcp-terraform/data.tf`

**Step 1: Create data.tf for existing GitHub OAuth**

```hcl
// data.tf - Data sources for existing resources

data "tfe_oauth_client" "github" {
  organization     = var.organization
  service_provider = "github"
}
```

**Step 2: Create imports.tf for existing workspaces**

```hcl
// imports.tf - Import blocks for existing workspaces

import {
  to = tfe_workspace.this["vault"]
  id = "fzymgc-house/vault"
}

import {
  to = tfe_workspace.this["authentik"]
  id = "fzymgc-house/authentik"
}

import {
  to = tfe_workspace.this["cloudflare"]
  id = "fzymgc-house/cloudflare"
}

import {
  to = tfe_workspace.this["cluster-bootstrap"]
  id = "fzymgc-house/cluster-bootstrap"
}
```

**Step 3: Create workspaces.tf**

```hcl
// workspaces.tf - Workspace configuration

locals {
  all_workspaces = {
    vault = {
      dir  = "tf/vault"
      tags = ["main-cluster", "vault"]
    }
    authentik = {
      dir  = "tf/authentik"
      tags = ["main-cluster", "authentik"]
    }
    grafana = {
      dir  = "tf/grafana"
      tags = ["main-cluster", "grafana"]
    }
    cloudflare = {
      dir  = "tf/cloudflare"
      tags = ["main-cluster", "cloudflared"]
    }
    core-services = {
      dir  = "tf/core-services"
      tags = ["main-cluster", "core-services"]
    }
    cluster-bootstrap = {
      dir  = "tf/cluster-bootstrap"
      tags = ["main-cluster", "bootstrap"]
    }
  }
}

resource "tfe_workspace" "this" {
  for_each = local.all_workspaces

  name              = each.key
  organization      = var.organization
  working_directory = each.value.dir
  tag_names         = each.value.tags

  # Agent execution mode
  execution_mode = "agent"
  agent_pool_id  = tfe_agent_pool.main.id

  # VCS-driven workflow
  auto_apply            = true
  speculative_enabled   = true
  file_triggers_enabled = true

  vcs_repo {
    identifier     = var.github_repo
    branch         = "main"
    oauth_token_id = data.tfe_oauth_client.github.oauth_token_id
  }
}
```

**Step 4: Validate**

Run: `terraform fmt -check tf/hcp-terraform/`
Expected: No formatting issues

**Step 5: Commit**

```bash
git add tf/hcp-terraform/data.tf tf/hcp-terraform/imports.tf tf/hcp-terraform/workspaces.tf
git commit -m "feat(hcp-terraform): add workspace imports and VCS configuration"
```

---

### Task 1.4: Create Notification Configuration

**Files:**
- Create: `tf/hcp-terraform/notifications.tf`

**Step 1: Create notifications.tf**

```hcl
// notifications.tf - Discord notification configuration via Cloudflare Worker

resource "tfe_notification_configuration" "discord" {
  for_each = tfe_workspace.this

  workspace_id     = each.value.id
  name             = "discord"
  enabled          = true
  destination_type = "generic"
  url              = var.discord_webhook_url

  triggers = [
    "run:planning",
    "run:applying",
    "run:completed",
    "run:errored",
  ]
}
```

**Step 2: Validate**

Run: `terraform fmt -check tf/hcp-terraform/`
Expected: No formatting issues

**Step 3: Commit**

```bash
git add tf/hcp-terraform/notifications.tf
git commit -m "feat(hcp-terraform): add Discord notification configuration"
```

---

## Phase 2: Vault OIDC Configuration

Add JWT auth method and per-workspace roles to the Vault module.

### Task 2.1: Create JWT Auth Backend

**Files:**
- Create: `tf/vault/jwt-hcp-terraform.tf`

**Step 1: Create JWT auth backend configuration**

```hcl
// jwt-hcp-terraform.tf - HCP Terraform workload identity

resource "vault_jwt_auth_backend" "hcp_terraform" {
  path               = "jwt-hcp-terraform"
  type               = "jwt"
  oidc_discovery_url = "https://app.terraform.io"
  bound_issuer       = "https://app.terraform.io"
  description        = "HCP Terraform workload identity for dynamic credentials"
}
```

**Step 2: Validate**

Run: `terraform fmt -check tf/vault/`
Expected: No formatting issues

**Step 3: Commit**

```bash
git add tf/vault/jwt-hcp-terraform.tf
git commit -m "feat(vault): add HCP Terraform JWT auth backend"
```

---

### Task 2.2: Create Per-Workspace Vault Roles

**Files:**
- Modify: `tf/vault/jwt-hcp-terraform.tf`

**Step 1: Add Vault role**

Append to `tf/vault/jwt-hcp-terraform.tf`:

```hcl
resource "vault_jwt_auth_backend_role" "tfc_vault" {
  backend   = vault_jwt_auth_backend.hcp_terraform.path
  role_name = "tfc-vault"

  bound_audiences = ["vault.workload.identity"]
  bound_claims = {
    sub = "organization:fzymgc-house:project:*:workspace:vault:run_phase:*"
  }

  user_claim     = "terraform_workspace_name"
  role_type      = "jwt"
  token_ttl      = 1200
  token_policies = ["terraform-vault-admin"]
}

resource "vault_jwt_auth_backend_role" "tfc_authentik" {
  backend   = vault_jwt_auth_backend.hcp_terraform.path
  role_name = "tfc-authentik"

  bound_audiences = ["vault.workload.identity"]
  bound_claims = {
    sub = "organization:fzymgc-house:project:*:workspace:authentik:run_phase:*"
  }

  user_claim     = "terraform_workspace_name"
  role_type      = "jwt"
  token_ttl      = 1200
  token_policies = ["terraform-authentik-admin"]
}

resource "vault_jwt_auth_backend_role" "tfc_grafana" {
  backend   = vault_jwt_auth_backend.hcp_terraform.path
  role_name = "tfc-grafana"

  bound_audiences = ["vault.workload.identity"]
  bound_claims = {
    sub = "organization:fzymgc-house:project:*:workspace:grafana:run_phase:*"
  }

  user_claim     = "terraform_workspace_name"
  role_type      = "jwt"
  token_ttl      = 1200
  token_policies = ["terraform-grafana-admin"]
}

resource "vault_jwt_auth_backend_role" "tfc_cloudflare" {
  backend   = vault_jwt_auth_backend.hcp_terraform.path
  role_name = "tfc-cloudflare"

  bound_audiences = ["vault.workload.identity"]
  bound_claims = {
    sub = "organization:fzymgc-house:project:*:workspace:cloudflare:run_phase:*"
  }

  user_claim     = "terraform_workspace_name"
  role_type      = "jwt"
  token_ttl      = 1200
  token_policies = ["terraform-cloudflare-admin"]
}

resource "vault_jwt_auth_backend_role" "tfc_core_services" {
  backend   = vault_jwt_auth_backend.hcp_terraform.path
  role_name = "tfc-core-services"

  bound_audiences = ["vault.workload.identity"]
  bound_claims = {
    sub = "organization:fzymgc-house:project:*:workspace:core-services:run_phase:*"
  }

  user_claim     = "terraform_workspace_name"
  role_type      = "jwt"
  token_ttl      = 1200
  token_policies = ["terraform-core-services-admin"]
}
```

**Step 2: Validate**

Run: `terraform fmt -check tf/vault/`
Expected: No formatting issues

**Step 3: Commit**

```bash
git add tf/vault/jwt-hcp-terraform.tf
git commit -m "feat(vault): add per-workspace OIDC roles for HCP Terraform"
```

---

### Task 2.3: Create Vault Policies for Terraform Workspaces

**Files:**
- Create: `tf/vault/policy-terraform-workspaces.tf`

**Step 1: Create policies**

Note: These policies define what each HCP TF workspace can access. Adjust paths based on actual secret paths used by each module.

```hcl
// policy-terraform-workspaces.tf - Policies for HCP Terraform workspace OIDC auth

# Vault workspace - manages Vault configuration
data "vault_policy_document" "terraform_vault_admin" {
  rule {
    path         = "auth/*"
    capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    description  = "Manage auth methods"
  }
  rule {
    path         = "sys/auth/*"
    capabilities = ["create", "read", "update", "delete", "sudo"]
    description  = "Manage auth method configuration"
  }
  rule {
    path         = "sys/policies/*"
    capabilities = ["create", "read", "update", "delete", "list"]
    description  = "Manage policies"
  }
  rule {
    path         = "identity/*"
    capabilities = ["create", "read", "update", "delete", "list"]
    description  = "Manage identity entities and groups"
  }
  rule {
    path         = "secret/data/fzymgc-house/*"
    capabilities = ["read", "list"]
    description  = "Read secrets for configuration"
  }
}

resource "vault_policy" "terraform_vault_admin" {
  name   = "terraform-vault-admin"
  policy = data.vault_policy_document.terraform_vault_admin.hcl
}

# Authentik workspace - manages Authentik secrets
data "vault_policy_document" "terraform_authentik_admin" {
  rule {
    path         = "secret/data/fzymgc-house/cluster/authentik"
    capabilities = ["read", "list"]
    description  = "Read Authentik secrets"
  }
  rule {
    path         = "secret/metadata/fzymgc-house/cluster/authentik"
    capabilities = ["read", "list"]
    description  = "Read Authentik secret metadata"
  }
}

resource "vault_policy" "terraform_authentik_admin" {
  name   = "terraform-authentik-admin"
  policy = data.vault_policy_document.terraform_authentik_admin.hcl
}

# Grafana workspace - manages Grafana secrets
data "vault_policy_document" "terraform_grafana_admin" {
  rule {
    path         = "secret/data/fzymgc-house/cluster/grafana"
    capabilities = ["read", "list"]
    description  = "Read Grafana secrets"
  }
  rule {
    path         = "secret/metadata/fzymgc-house/cluster/grafana"
    capabilities = ["read", "list"]
    description  = "Read Grafana secret metadata"
  }
}

resource "vault_policy" "terraform_grafana_admin" {
  name   = "terraform-grafana-admin"
  policy = data.vault_policy_document.terraform_grafana_admin.hcl
}

# Cloudflare workspace - manages Cloudflare secrets
data "vault_policy_document" "terraform_cloudflare_admin" {
  rule {
    path         = "secret/data/fzymgc-house/cluster/cloudflare"
    capabilities = ["read", "list"]
    description  = "Read Cloudflare secrets"
  }
  rule {
    path         = "secret/metadata/fzymgc-house/cluster/cloudflare"
    capabilities = ["read", "list"]
    description  = "Read Cloudflare secret metadata"
  }
}

resource "vault_policy" "terraform_cloudflare_admin" {
  name   = "terraform-cloudflare-admin"
  policy = data.vault_policy_document.terraform_cloudflare_admin.hcl
}

# Core-services workspace - manages core service secrets
data "vault_policy_document" "terraform_core_services_admin" {
  rule {
    path         = "secret/data/fzymgc-house/cluster/*"
    capabilities = ["read", "list"]
    description  = "Read cluster secrets"
  }
  rule {
    path         = "secret/metadata/fzymgc-house/cluster/*"
    capabilities = ["read", "list"]
    description  = "Read cluster secret metadata"
  }
}

resource "vault_policy" "terraform_core_services_admin" {
  name   = "terraform-core-services-admin"
  policy = data.vault_policy_document.terraform_core_services_admin.hcl
}
```

**Step 2: Validate**

Run: `terraform fmt -check tf/vault/`
Expected: No formatting issues

**Step 3: Commit**

```bash
git add tf/vault/policy-terraform-workspaces.tf
git commit -m "feat(vault): add Vault policies for HCP Terraform workspaces"
```

---

## Phase 3: Agent Deployment (ArgoCD)

Deploy the HCP Terraform Operator and agent via ArgoCD.

### Task 3.1: Create HCP Terraform Operator App Config

**Files:**
- Create: `argocd/app-configs/hcp-terraform-operator/kustomization.yaml`
- Create: `argocd/app-configs/hcp-terraform-operator/namespace.yaml`
- Create: `argocd/app-configs/hcp-terraform-operator/values.yaml`
- Create: `argocd/app-configs/hcp-terraform-operator/external-secrets.yaml`

**Step 1: Create namespace.yaml**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: hcp-terraform
  labels:
    app.kubernetes.io/name: hcp-terraform-operator
```

**Step 2: Create external-secrets.yaml**

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: hcp-terraform-agent-token
  namespace: hcp-terraform
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: hcp-terraform-agent-token
    creationPolicy: Owner
  data:
    - secretKey: token
      remoteRef:
        key: secret/fzymgc-house/cluster/hcp-terraform
        property: agent_token
```

**Step 3: Create values.yaml**

```yaml
# HCP Terraform Operator Helm values
# See: https://github.com/hashicorp/hcp-terraform-operator

replicaCount: 1

resources:
  limits:
    cpu: 500m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

**Step 4: Create kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: hcp-terraform

resources:
  - namespace.yaml
  - external-secrets.yaml

# Helm values will be referenced by ArgoCD application
```

**Step 5: Commit**

```bash
git add argocd/app-configs/hcp-terraform-operator/
git commit -m "feat(argocd): add HCP Terraform Operator app config"
```

---

### Task 3.2: Create Agent Pool CRD

**Files:**
- Create: `argocd/app-configs/hcp-terraform-operator/agent-pool.yaml`
- Modify: `argocd/app-configs/hcp-terraform-operator/kustomization.yaml`

**Step 1: Create agent-pool.yaml**

```yaml
apiVersion: app.terraform.io/v1alpha2
kind: AgentPool
metadata:
  name: fzymgc-house-agents
  namespace: hcp-terraform
spec:
  organization: fzymgc-house
  token:
    secretKeyRef:
      name: hcp-terraform-agent-token
      key: token
  agentTokens:
    - name: k8s-agent
  agentDeployment:
    replicas: 1
    spec:
      containers:
        - name: tfc-agent
          resources:
            requests:
              memory: "256Mi"
              cpu: "250m"
            limits:
              memory: "512Mi"
              cpu: "500m"
```

**Step 2: Update kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: hcp-terraform

resources:
  - namespace.yaml
  - external-secrets.yaml
  - agent-pool.yaml

# Helm values will be referenced by ArgoCD application
```

**Step 3: Commit**

```bash
git add argocd/app-configs/hcp-terraform-operator/
git commit -m "feat(argocd): add AgentPool CRD for HCP Terraform"
```

---

### Task 3.3: Create ArgoCD Application

**Files:**
- Create: `argocd/cluster-app/templates/hcp-terraform-operator.yaml`

**Step 1: Create ArgoCD application**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hcp-terraform-operator
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  ignoreDifferences:
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      jsonPointers:
        - /metadata/annotations/kubectl.kubernetes.io~1last-applied-configuration
        - /status
  sources:
    - repoURL: https://helm.releases.hashicorp.com
      chart: hcp-terraform-operator
      targetRevision: 0.6.0
      helm:
        valueFiles:
          - $values/argocd/app-configs/hcp-terraform-operator/values.yaml
    - repoURL: https://github.com/fzymgc-house/selfhosted-cluster
      targetRevision: HEAD
      ref: values
    - repoURL: https://github.com/fzymgc-house/selfhosted-cluster
      targetRevision: HEAD
      path: argocd/app-configs/hcp-terraform-operator
  destination:
    server: https://kubernetes.default.svc
    namespace: hcp-terraform
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

**Step 2: Commit**

```bash
git add argocd/cluster-app/templates/hcp-terraform-operator.yaml
git commit -m "feat(argocd): add HCP Terraform Operator ArgoCD application"
```

---

## Phase 4: Cloudflare Worker for Discord

Create the webhook transformer.

### Task 4.1: Create Cloudflare Worker

**Files:**
- Create: `cloudflare/workers/hcp-terraform-discord/worker.js`
- Create: `cloudflare/workers/hcp-terraform-discord/wrangler.toml`

**Step 1: Create worker.js**

```javascript
// HCP Terraform to Discord webhook transformer

export default {
  async fetch(request, env) {
    // Only accept POST requests
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    try {
      const payload = await request.json();
      
      // Extract notification data
      const notification = payload.notifications?.[0];
      if (!notification) {
        return new Response("No notification data", { status: 400 });
      }

      // Color mapping for run status
      const colors = {
        "planned": 0x3498db,      // blue
        "applied": 0x2ecc71,      // green
        "errored": 0xe74c3c,      // red
        "canceled": 0x95a5a6,     // gray
        "planning": 0xf39c12,     // orange
        "applying": 0xf39c12,     // orange
        "discarded": 0x95a5a6,    // gray
      };

      const statusEmoji = {
        "planned": "📋",
        "applied": "✅",
        "errored": "❌",
        "canceled": "🚫",
        "planning": "🔄",
        "applying": "🔄",
        "discarded": "🗑️",
      };

      const status = notification.run_status || "unknown";
      const color = colors[status] || 0x7289da;
      const emoji = statusEmoji[status] || "❓";

      // Build Discord embed
      const embed = {
        embeds: [{
          title: `${emoji} Terraform ${status.charAt(0).toUpperCase() + status.slice(1)}`,
          description: [
            `**Workspace:** ${payload.workspace_name || "unknown"}`,
            `**Run:** [${notification.run_id}](${notification.run_url})`,
            notification.run_message ? `**Message:** ${notification.run_message}` : null,
          ].filter(Boolean).join("\n"),
          color: color,
          timestamp: new Date().toISOString(),
          footer: {
            text: "HCP Terraform",
          },
        }],
      };

      // Send to Discord
      const discordResponse = await fetch(env.DISCORD_WEBHOOK_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(embed),
      });

      if (!discordResponse.ok) {
        console.error("Discord error:", await discordResponse.text());
        return new Response("Discord webhook failed", { status: 502 });
      }

      return new Response("OK", { status: 200 });
    } catch (error) {
      console.error("Error processing webhook:", error);
      return new Response("Internal error", { status: 500 });
    }
  },
};
```

**Step 2: Create wrangler.toml**

```toml
name = "hcp-terraform-discord"
main = "worker.js"
compatibility_date = "2024-01-01"

# Secret: DISCORD_WEBHOOK_URL
# Set via: wrangler secret put DISCORD_WEBHOOK_URL
```

**Step 3: Commit**

```bash
git add cloudflare/workers/hcp-terraform-discord/
git commit -m "feat(cloudflare): add HCP Terraform Discord webhook worker"
```

---

## Phase 5: Module Provider Updates

Update each module to use OIDC authentication.

### Task 5.1: Update Vault Module Provider

**Files:**
- Modify: `tf/vault/terraform.tf`
- Modify: `tf/vault/variables.tf`

**Step 1: Update terraform.tf**

Replace the current provider configuration with OIDC support:

```hcl
// terraform.tf - Provider and backend configuration

terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      tags = ["main-cluster", "vault"]
    }
  }
}

provider "vault" {
  address = var.vault_addr

  # Use OIDC when running in HCP TF, fallback to token for local dev
  dynamic "auth_login_jwt" {
    for_each = var.tfc_workload_identity_token_path != "" ? [1] : []
    content {
      role = "tfc-vault"
      jwt  = file(var.tfc_workload_identity_token_path)
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/configs/fzymgc-house-admin.yml"
  config_context = "fzymgc-house"
}
```

**Step 2: Update variables.tf**

Add OIDC variable:

```hcl
variable "vault_addr" {
  description = "Vault server address"
  type        = string
  default     = "https://vault.fzymgc.house"
}

variable "tfc_workload_identity_token_path" {
  description = "Path to HCP TF workload identity JWT (empty for local dev)"
  type        = string
  default     = ""
}
```

**Step 3: Validate**

Run: `terraform fmt -check tf/vault/`
Expected: No formatting issues

**Step 4: Commit**

```bash
git add tf/vault/terraform.tf tf/vault/variables.tf
git commit -m "feat(vault): add OIDC provider config for HCP Terraform"
```

---

### Task 5.2: Update Grafana Module (Add Cloud Backend)

**Files:**
- Modify: `tf/grafana/terraform.tf`
- Modify: `tf/grafana/variables.tf`

**Step 1: Update terraform.tf**

Replace `backend "local" {}` with cloud and OIDC:

```hcl
// terraform.tf - Provider and backend configuration

terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      tags = ["main-cluster", "grafana"]
    }
  }
}

provider "vault" {
  address = var.vault_addr

  dynamic "auth_login_jwt" {
    for_each = var.tfc_workload_identity_token_path != "" ? [1] : []
    content {
      role = "tfc-grafana"
      jwt  = file(var.tfc_workload_identity_token_path)
    }
  }
}

provider "grafana" {
  url  = var.grafana_url
  auth = data.vault_generic_secret.grafana.data["admin_password"]
}
```

**Step 2: Update variables.tf**

Add required variables:

```hcl
variable "vault_addr" {
  description = "Vault server address"
  type        = string
  default     = "https://vault.fzymgc.house"
}

variable "grafana_url" {
  description = "Grafana server URL"
  type        = string
  default     = "https://grafana.fzymgc.house"
}

variable "tfc_workload_identity_token_path" {
  description = "Path to HCP TF workload identity JWT (empty for local dev)"
  type        = string
  default     = ""
}
```

**Step 3: Validate**

Run: `terraform fmt -check tf/grafana/`
Expected: No formatting issues

**Step 4: Commit**

```bash
git add tf/grafana/terraform.tf tf/grafana/variables.tf
git commit -m "feat(grafana): migrate to HCP TF cloud backend with OIDC"
```

---

### Task 5.3: Update Core-Services Module (Add Cloud Backend)

**Files:**
- Create: `tf/core-services/terraform.tf` (currently empty)
- Modify: `tf/core-services/variables.tf`

**Step 1: Create terraform.tf**

```hcl
// terraform.tf - Provider and backend configuration

terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      tags = ["main-cluster", "core-services"]
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/configs/fzymgc-house-admin.yml"
  config_context = "fzymgc-house"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/configs/fzymgc-house-admin.yml"
    config_context = "fzymgc-house"
  }
}
```

**Step 2: Validate**

Run: `terraform fmt -check tf/core-services/`
Expected: No formatting issues

**Step 3: Commit**

```bash
git add tf/core-services/terraform.tf
git commit -m "feat(core-services): add HCP TF cloud backend configuration"
```

---

### Task 5.4: Update Remaining Modules (Authentik, Cloudflare)

**Files:**
- Modify: `tf/authentik/terraform.tf`
- Modify: `tf/authentik/variables.tf`
- Modify: `tf/cloudflare/terraform.tf`
- Modify: `tf/cloudflare/variables.tf`

Apply the same OIDC pattern to each module. The key changes are:
1. Add `tfc_workload_identity_token_path` variable
2. Add dynamic `auth_login_jwt` block to vault provider
3. Use appropriate role name (`tfc-authentik`, `tfc-cloudflare`)

**Step 1: Commit after each module update**

```bash
git add tf/authentik/terraform.tf tf/authentik/variables.tf
git commit -m "feat(authentik): add OIDC provider config for HCP Terraform"

git add tf/cloudflare/terraform.tf tf/cloudflare/variables.tf
git commit -m "feat(cloudflare): add OIDC provider config for HCP Terraform"
```

---

## Phase 6: Store Agent Token in Vault

### Task 6.1: Store Agent Token

**Manual step** - Run after `tf/hcp-terraform` is applied:

```bash
# Get the agent token from terraform output
cd tf/hcp-terraform
AGENT_TOKEN=$(terraform output -raw agent_token)

# Store in Vault
vault kv put secret/fzymgc-house/cluster/hcp-terraform agent_token="$AGENT_TOKEN"
```

---

## Phase 7: Documentation Updates

### Task 7.1: Update docs/windmill.md

**Files:**
- Modify: `docs/windmill.md`

Add deprecation notice and reference to HCP TF:

```markdown
> **⚠️ DEPRECATED**: Terraform execution has migrated to HCP Terraform. See the HCP Terraform migration design doc for details. Windmill flows are archived but not deleted for rollback capability.
```

### Task 7.2: Create docs/hcp-terraform.md

**Files:**
- Create: `docs/hcp-terraform.md`

Document the new HCP Terraform setup for ongoing operations.

---

## Execution Checklist

| Phase | Task | Status |
|-------|------|--------|
| 1 | Create tf/hcp-terraform module structure | ⬜ |
| 1 | Add agent pool configuration | ⬜ |
| 1 | Add workspace imports and configuration | ⬜ |
| 1 | Add notification configuration | ⬜ |
| 2 | Create JWT auth backend in Vault | ⬜ |
| 2 | Create per-workspace Vault roles | ⬜ |
| 2 | Create Vault policies for workspaces | ⬜ |
| 3 | Create ArgoCD app config for operator | ⬜ |
| 3 | Create AgentPool CRD | ⬜ |
| 3 | Create ArgoCD Application | ⬜ |
| 4 | Create Cloudflare Worker | ⬜ |
| 5 | Update Vault module provider | ⬜ |
| 5 | Update Grafana module (add cloud backend) | ⬜ |
| 5 | Update Core-Services module | ⬜ |
| 5 | Update Authentik and Cloudflare modules | ⬜ |
| 6 | Store agent token in Vault | ⬜ |
| 7 | Update documentation | ⬜ |
