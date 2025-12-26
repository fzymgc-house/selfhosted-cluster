# HCP Terraform Runners Investigation

## Summary

Evaluate deploying HCP Terraform self-hosted agents to replace Windmill-based Terraform automation. Agents would be deployed in both the Kubernetes cluster and on the NAS (as Docker Compose) to enable HCP Terraform to remotely manage infrastructure in private networks.

## Background

Currently, Terraform automation is handled by Windmill (`windmill/f/terraform/`) with:
- Two-workspace pattern (staging/prod)
- Discord-based approval notifications
- S3 (R2) state storage
- Git-based promotion workflow

## What Are HCP Terraform Agents?

Self-hosted execution environments that run Terraform operations locally while integrating with HCP Terraform's cloud management plane. They solve the problem of managing infrastructure in private/isolated networks without exposing those networks to the public internet.

| Aspect | Cloud Runners (Default) | Self-Hosted Agents |
|--------|------------------------|-------------------|
| Execution Location | HashiCorp's managed VMs | Your infrastructure |
| Network Access | Public internet only | Private networks, on-prem, VPCs |
| Control | HashiCorp-managed | You manage lifecycle, scaling |
| Connectivity | Inbound from HCP | **Outbound only** to HCP (secure) |
| Use Case | Public cloud APIs | Private infra, Vault, K8s APIs |

## Architecture

```
┌─────────────────────┐     ┌──────────────────────────────┐
│   HCP Terraform     │     │  Private Network             │
│   (Cloud Control)   │◄────┤                              │
│                     │     │  ┌─────────────────────────┐ │
│   - State storage   │     │  │  HCP TF Agent           │ │
│   - Run history     │     │  │  (outbound only)        │ │
│   - Policies        │     │  │       │                 │ │
│   - VCS integration │     │  │       ▼                 │ │
└─────────────────────┘     │  │  ┌─────────────────┐   │ │
                            │  │  │ Vault, K8s API, │   │ │
                            │  │  │ private infra   │   │ │
                            │  │  └─────────────────┘   │ │
                            │  └─────────────────────────┘ │
                            └──────────────────────────────┘
```

## Comparison: Windmill vs HCP Terraform Agents

| Feature | Windmill (Current) | HCP Terraform Agents |
|---------|-------------------|---------------------|
| Execution | In-cluster workers | Self-hosted agents |
| State Storage | Local/S3 (R2) | HCP-managed (encrypted) |
| Approval Workflow | Discord bot notifications | HCP UI, Sentinel policies |
| VCS Integration | Git sync to staging branch | Native GitHub/GitLab VCS |
| Concurrency | Multiple workers | Tier-limited (Free: 1 agent) |
| Policy-as-Code | Manual/custom | Sentinel (built-in) |
| Cost Model | Self-hosted (infra costs) | Free tier + resource-based |
| Secrets | Vault integration (manual) | Dynamic credentials (native OIDC) |
| Deployment | ArgoCD manages Windmill | You manage agents |

## Benefits

| Benefit | Details |
|---------|---------|
| Private Network Access | Direct access to `vault.fzymgc.house`, Kubernetes API (`192.168.20.140`), without public exposure |
| Centralized State | Enterprise-grade state management, locking, versioning |
| Native Vault Integration | Dynamic credentials via OIDC/JWT - no static tokens |
| Audit Trail | Complete run history, policy checks, cost estimation |
| Collaboration | Multiple team members, workspace permissions |
| VCS Workflows | Automatic plan on PR, apply on merge |
| Sentinel Policies | Policy-as-code for governance |
| No Inbound Traffic | Agents poll outbound only - firewall-friendly |

## Detriments / Considerations

| Concern | Details |
|---------|---------|
| Free Tier Limits | 1 concurrent agent, 500 resources/month |
| Concurrency Bottleneck | Sequential runs can slow delivery with multiple workspaces |
| External Dependency | Relies on HCP uptime (though agents cache work) |
| Token Management | Agent pool tokens need rotation/security |
| Learning Curve | Different workflow from Windmill flows |
| Resource Counting | Each S3 rule, SG rule counts separately (cost concern at scale) |

## Deployment Options

### Option A: Kubernetes Operator (for K8s cluster)

The HCP Terraform Operator for Kubernetes provides native lifecycle management:

```yaml
apiVersion: app.terraform.io/v1alpha2
kind: AgentPool
metadata:
  name: k8s-cluster-agents
spec:
  name: fzymgc-house-k8s
  organization: your-org
  token:
    secretKeyRef:
      name: hcp-terraform-token
      key: token
  agentDeployment:
    replicas: 1
    spec:
      containers:
        - name: tfc-agent
          image: hashicorp/tfc-agent:latest
  autoscaling:
    minReplicas: 0      # Scale to zero when idle
    maxReplicas: 3
    cooldownPeriod: 10m
```

Install via Helm:
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install tfc-operator hashicorp/hcp-terraform-operator --wait
```

### Option B: Docker Compose (for NAS)

```yaml
version: "3.8"
services:
  tfc-agent:
    image: hashicorp/tfc-agent:latest
    restart: unless-stopped
    environment:
      TFC_AGENT_TOKEN: ${TFC_AGENT_TOKEN}
      TFC_AGENT_NAME: nas-agent
      TFC_AGENT_LOG_LEVEL: info
    volumes:
      - ./custom-providers:/home/tfc-agent/.terraform.d/plugins
```

## Vault Dynamic Credentials Integration

HCP Terraform supports native OIDC integration with Vault:

```hcl
resource "vault_jwt_auth_backend" "tfc" {
  path               = "jwt-tfc"
  oidc_discovery_url = "https://app.terraform.io"
  bound_issuer       = "https://app.terraform.io"
}

resource "vault_jwt_auth_backend_role" "tfc_workspaces" {
  backend        = vault_jwt_auth_backend.tfc.path
  role_name      = "tfc-workspaces"
  token_policies = ["terraform-admin"]

  bound_audiences   = ["vault.workload.identity"]
  bound_claims_type = "glob"
  bound_claims = {
    sub = "organization:your-org:project:*:workspace:*:run_phase:*"
  }

  user_claim = "terraform_full_workspace"
  role_type  = "jwt"
  token_ttl  = 1200
}
```

## Module Suitability

| Module | Recommendation | Rationale |
|--------|---------------|-----------|
| `tf/vault` | ✅ Good fit | Private network access, native Vault integration |
| `tf/authentik` | ✅ Good fit | Private network access required |
| `tf/grafana` | ✅ Good fit | Private network access required |
| `tf/core-services` | ✅ Good fit | Kubernetes API access |
| `tf/cloudflare` | ⚠️ Optional | Could use cloud runners (public API) |
| `tf/cluster-bootstrap` | ⚠️ Complex | Deploys infrastructure that agents depend on |

## Suggested Hybrid Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    HCP Terraform                            │
│  ┌──────────────────┐  ┌──────────────────┐                │
│  │ Private Infra    │  │ Public APIs      │                │
│  │ Workspaces       │  │ Workspaces       │                │
│  │ (agent pool)     │  │ (cloud runners)  │                │
│  └────────┬─────────┘  └────────┬─────────┘                │
└───────────┼─────────────────────┼──────────────────────────┘
            │                     │
            ▼                     ▼
   ┌────────────────┐    ┌────────────────┐
   │ K8s Agent Pool │    │ HCP Cloud VMs  │
   │ (autoscaling)  │    │ (managed)      │
   │ - Vault        │    │ - Cloudflare   │
   │ - K8s/Authentik│    │                │
   │ - Grafana      │    │                │
   └────────────────┘    └────────────────┘

   ┌────────────────┐
   │ NAS Agent      │
   │ (docker-compose)
   │ - Backup jobs  │
   │ - Local infra  │
   └────────────────┘
```

## Cost Considerations

| Tier | Agents | Resources | Monthly Cost |
|------|--------|-----------|--------------|
| Free | 1 | 500/month | $0 |
| Standard | Varies | Unlimited | ~$0.00014/resource/hour |
| Plus | Varies | Unlimited | Higher + Sentinel |

With ~6 modules and moderate change frequency, the Free tier may suffice initially.

## Migration Path

1. **Phase 1**: Deploy K8s agent pool with operator (single agent, free tier)
2. **Phase 2**: Migrate one simple module (e.g., `tf/grafana`) as proof-of-concept
3. **Phase 3**: Set up Vault dynamic credentials integration
4. **Phase 4**: Migrate remaining private-network modules
5. **Phase 5**: Deploy NAS agent for NAS-specific automation
6. **Phase 6**: Evaluate: keep Windmill for orchestration, or fully migrate?

## Decision Factors

- **Keep Windmill if**: You value the custom approval workflow, Discord notifications, and don't mind managing state yourself
- **Switch to HCP TF if**: You want enterprise-grade state management, native Vault OIDC, and centralized visibility
- **Hybrid approach**: Use HCP TF for infrastructure, keep Windmill for non-Terraform automation

## References

- [HCP Terraform Agents Overview](https://developer.hashicorp.com/terraform/cloud-docs/agents)
- [Install and Run HCP Terraform Agents](https://developer.hashicorp.com/terraform/cloud-docs/agents/agents)
- [HCP Terraform Agent Requirements](https://developer.hashicorp.com/terraform/cloud-docs/agents/requirements)
- [HCP Terraform Operator for Kubernetes](https://developer.hashicorp.com/terraform/cloud-docs/integrations/kubernetes)
- [Manage Agent Pools with Kubernetes Operator v2](https://developer.hashicorp.com/terraform/tutorials/kubernetes/kubernetes-operator-v2-agentpool)
- [Dynamic Credentials with Vault Provider](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/vault-configuration)
- [HCP Terraform Plans and Features](https://developer.hashicorp.com/terraform/cloud-docs/overview)
- [HCP Terraform Operator GitHub](https://github.com/hashicorp/hcp-terraform-operator)

## Tasks

- [ ] Sign up for HCP Terraform (free tier)
- [ ] Create organization and agent pool
- [ ] Deploy HCP Terraform Operator to K8s cluster
- [ ] Configure agent pool CRD with autoscaling
- [ ] Set up Vault JWT auth backend for dynamic credentials
- [ ] Migrate `tf/grafana` as proof-of-concept
- [ ] Evaluate results and decide on full migration
- [ ] (Optional) Deploy Docker Compose agent on NAS
