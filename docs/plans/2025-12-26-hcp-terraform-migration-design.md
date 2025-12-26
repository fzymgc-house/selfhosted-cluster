# HCP Terraform Migration Design

Migrate Terraform execution from Windmill to HCP Terraform self-hosted agents.

## Goals

- **Proper concurrency**: HCP TF native queuing replaces Windmill's limited concurrent_limit
- **Dynamic credentials**: Vault OIDC workload identity replaces static tokens
- **VCS-driven workflow**: Auto plan on PR, auto apply on merge
- **Keep Discord notifications**: Cloudflare Worker transforms HCP webhooks

## Current State

| Module | Backend | Status |
|--------|---------|--------|
| `tf/vault` | HCP Cloud | Import |
| `tf/authentik` | HCP Cloud | Import |
| `tf/cloudflare` | HCP Cloud | Import |
| `tf/cluster-bootstrap` | HCP Cloud | Import |
| `tf/grafana` | Local | Create + migrate state |
| `tf/core-services` | Empty | Create |

HCP TF organization `fzymgc-house` exists with GitHub OAuth connected. Workspaces are CLI-driven (local execution mode).

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           GitHub                                     │
│  PR Created/Updated ─────────────────────┐                          │
│  PR Merged to main ──────────────────────┼──┐                       │
└──────────────────────────────────────────┼──┼───────────────────────┘
                                           │  │
                                           ▼  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        HCP Terraform                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │
│  │ vault ws    │  │ authentik   │  │ grafana ws  │  ... (6 total)   │
│  │ path:tf/vault│ │ ws          │  │             │                  │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                  │
│         │                │                │                          │
│         └────────────────┼────────────────┘                          │
│                          ▼                                           │
│                   ┌─────────────┐      ┌─────────────┐              │
│                   │ Agent Pool  │─────▶│ Run Queue   │              │
│                   └─────────────┘      └──────┬──────┘              │
│                                               │                      │
│                   Webhook ────────────────────┼──────────────────────┤
└───────────────────────┬───────────────────────┼──────────────────────┘
                        │                       │
                        ▼                       ▼
┌───────────────────────────────┐    ┌─────────────────────────────────┐
│     Cloudflare Worker         │    │       Kubernetes Cluster         │
│  Transform → Discord Webhook  │    │  ┌─────────────────────────┐    │
└───────────────────────────────┘    │  │ HCP TF Operator         │    │
                        │            │  │  └─▶ Agent Pod(s)       │    │
                        ▼            │  │       │                 │    │
                ┌───────────┐        │  │       ▼                 │    │
                │  Discord  │        │  │  ┌─────────┐            │    │
                │  Channel  │        │  │  │ Vault   │◀── OIDC    │    │
                └───────────┘        │  │  └─────────┘            │    │
                                     │  └─────────────────────────┘    │
                                     └─────────────────────────────────┘
```

**Flow:**
1. PR triggers speculative plan (free, shown as PR comment)
2. Merge to main triggers plan + auto-apply
3. HCP queues run, dispatches to agent in K8s
4. Agent authenticates to Vault via OIDC JWT
5. Terraform executes with dynamic credentials
6. HCP webhook fires → Cloudflare Worker → Discord

## Component Design

### 1. Agent Deployment (Kubernetes)

Deploy via HCP Terraform Operator in dedicated namespace.

**ArgoCD Application:** `argocd/hcp-terraform-operator/`

```yaml
# kustomization.yaml
namespace: hcp-terraform
resources:
  - namespace.yaml
helmCharts:
  - name: hcp-terraform-operator
    repo: https://helm.releases.hashicorp.com
    version: "1.x.x"
    namespace: hcp-terraform
```

**AgentPool CRD:**

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

**Agent Token Secret (ExternalSecret):**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: hcp-terraform-agent-token
  namespace: hcp-terraform
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  target:
    name: hcp-terraform-agent-token
  data:
    - secretKey: token
      remoteRef:
        key: secret/fzymgc-house/cluster/hcp-terraform
        property: agent_token
```

### 2. Vault OIDC Configuration

Add to `tf/vault` module. Creates JWT auth method and per-workspace roles.

**JWT Auth Backend:**

```hcl
resource "vault_jwt_auth_backend" "hcp_terraform" {
  path               = "jwt-hcp-terraform"
  type               = "jwt"
  oidc_discovery_url = "https://app.terraform.io"
  bound_issuer       = "https://app.terraform.io"
  description        = "HCP Terraform workload identity"
}
```

**Per-Workspace Roles:**

| Role | Bound Workspace | Policy |
|------|-----------------|--------|
| `tfc-vault` | `vault` | `terraform-vault-admin` |
| `tfc-authentik` | `authentik` | `terraform-authentik-admin` |
| `tfc-grafana` | `grafana` | `terraform-grafana-admin` |
| `tfc-cloudflare` | `cloudflare` | `terraform-cloudflare-admin` |
| `tfc-core-services` | `core-services` | `terraform-core-services-admin` |

**Example Role:**

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
```

**Provider Config (each module):**

```hcl
provider "vault" {
  address = "https://vault.fzymgc.house"
  
  auth_login_jwt {
    role = "tfc-vault"
    jwt  = file(var.tfc_workload_identity_token_path)
  }
}

variable "tfc_workload_identity_token_path" {
  type    = string
  default = "/var/run/secrets/tokens/vault-token"
}
```

### 3. Discord Notifications (Cloudflare Worker)

Transform HCP TF webhook payloads to Discord embed format.

**Worker Logic:**

```javascript
export default {
  async fetch(request, env) {
    const payload = await request.json();
    
    const color = {
      "applied": 0x2ecc71,
      "planned": 0x3498db,
      "errored": 0xe74c3c,
      "canceled": 0x95a5a6,
    }[payload.notifications[0].run_status] || 0x7289da;

    const embed = {
      embeds: [{
        title: `Terraform ${payload.notifications[0].run_status}`,
        description: `**Workspace:** ${payload.workspace_name}\n**Run:** [${payload.run_id}](${payload.run_url})`,
        color: color,
        timestamp: new Date().toISOString(),
      }]
    };

    await fetch(env.DISCORD_WEBHOOK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(embed),
    });

    return new Response("OK", { status: 200 });
  }
};
```

**Deployment:** Manage via `tf/cloudflare` or separate worker config.

### 4. HCP TF Workspace Management

New module `tf/hcp-terraform` manages workspace configuration.

**Module Structure:**

```
tf/hcp-terraform/
├── terraform.tf
├── versions.tf
├── variables.tf
├── imports.tf        # Import blocks for existing workspaces
├── workspaces.tf
├── agent_pool.tf
├── notifications.tf
└── outputs.tf
```

**Import Existing Workspaces:**

```hcl
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

**Workspace Resource:**

```hcl
locals {
  all_workspaces = {
    vault             = { dir = "tf/vault",             tags = ["main-cluster", "vault"] }
    authentik         = { dir = "tf/authentik",         tags = ["main-cluster", "authentik"] }
    grafana           = { dir = "tf/grafana",           tags = ["main-cluster", "grafana"] }
    cloudflare        = { dir = "tf/cloudflare",        tags = ["main-cluster", "cloudflared"] }
    core-services     = { dir = "tf/core-services",     tags = ["main-cluster", "core-services"] }
    cluster-bootstrap = { dir = "tf/cluster-bootstrap", tags = ["main-cluster", "bootstrap"] }
  }
}

resource "tfe_workspace" "this" {
  for_each = local.all_workspaces
  
  name              = each.key
  organization      = var.organization
  working_directory = each.value.dir
  tag_names         = each.value.tags
  
  execution_mode = "agent"
  agent_pool_id  = tfe_agent_pool.main.id
  
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

**Use Existing GitHub Connection:**

```hcl
data "tfe_oauth_client" "github" {
  organization     = var.organization
  service_provider = "github"
}
```

**Agent Pool:**

```hcl
resource "tfe_agent_pool" "main" {
  name         = "fzymgc-house-k8s"
  organization = var.organization
}

resource "tfe_agent_token" "k8s" {
  agent_pool_id = tfe_agent_pool.main.id
  description   = "Kubernetes cluster agent"
}

output "agent_token" {
  value     = tfe_agent_token.k8s.token
  sensitive = true
}
```

## Migration Sequence

### Order

1. **vault** — Creates OIDC auth + all roles
2. **authentik** — Uses OIDC
3. **grafana** — Needs cloud backend migration
4. **core-services** — Needs cloud backend setup
5. **cloudflare** — Uses OIDC
6. **cluster-bootstrap** — Last (manages HCP TF operator)

### Phases

**Day 0: Prerequisites**
- Create `tf/hcp-terraform` module
- Deploy HCP TF Operator to cluster (ArgoCD)
- Store agent token in Vault
- Deploy Cloudflare Worker for Discord

**Day 1: Vault Migration**
- Run `tf/vault` locally to create OIDC auth + all roles
- Update vault workspace to agent mode
- Update vault provider to use OIDC
- Trigger run via HCP (validates OIDC works)
- Remove static `vault_terraform_token` from Windmill

**Day 2: Remaining Modules**
- Update each module's provider config for OIDC
- Migrate grafana/core-services to cloud backend
- Switch all workspaces to agent mode
- Test each with a dummy commit
- Archive Windmill terraform flows

### Rollback Plan

- Keep static Vault token valid for 1 week post-migration
- Workspaces can switch back to "local" execution mode
- Windmill flows archived (not deleted) until validated

## Cleanup After Migration

| Component | Action |
|-----------|--------|
| `windmill/f/terraform/` | Archive or delete |
| Windmill Discord bot config | Remove |
| S3 plan storage resources | Remove |
| `vault_terraform_token` | Revoke after validation |
| GitHub Actions for Windmill | Remove |

## Free Tier Considerations

| Limit | Value | Notes |
|-------|-------|-------|
| Concurrent agents | 1 | Runs queue sequentially |
| Resources/month | 500 | ~100/module × 5 = 500 if each runs once |
| Speculative plans | Unlimited | PRs are free |

Monitor usage; upgrade to Team ($20/user/month) if needed.
