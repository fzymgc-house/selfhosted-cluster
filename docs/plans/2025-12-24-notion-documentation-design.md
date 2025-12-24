# Design: Notion Documentation Structure

**Date:** 2025-12-24
**Status:** Completed

## Purpose

Create a Notion workspace that reflects the selfhosted-cluster repository documentation. The structure should be:
- **Human-readable**: Organized for operators and maintainers
- **AI-consumable**: Structured data that agents can query and use for context

Root page: **Home Lab** (ID: `17027a0a-d688-8053-b8cb-f2584d07c33c`)

## Deliverables

### 1. Home Lab Overview Page

Root page with:
- Quick reference table (IPs, URLs, credentials locations)
- Embedded architecture diagrams (from README)
- Links to sub-pages

### 2. Services Catalog Database

**Purpose:** Central registry of all services with DNS, endpoints, and status

| Property | Type | Description |
|----------|------|-------------|
| Name | Title | Service name |
| Category | Select | Platform, Application, Infrastructure, External |
| Hostname | Text | Primary DNS name |
| Alt Hostnames | Multi-select | Alternative DNS entries |
| Ingress Type | Select | Traefik IngressRoute, TCP Passthrough, Helm Managed, kube-vip VIP, Cloudflare Tunnel, External, None |
| Auth Method | Select | OIDC, Forward-Auth, Certificate, None |
| Vault Path | Text | Secret location (if applicable) |
| Namespace | Text | Kubernetes namespace |
| Status | Status | Operational, Degraded, Maintenance |
| Notes | Rich text | Additional context |

**Initial Data (29 services):**

| Name | Category | Hostname | Ingress | Auth |
|------|----------|----------|---------|------|
| Kubernetes API | Infrastructure | k8s-cluster.fzymgc.house | kube-vip VIP | Certificate |
| Vault | Platform | vault.fzymgc.house | TCP Passthrough | OIDC |
| Authentik | Platform | auth.fzymgc.house | Traefik IngressRoute | None |
| Grafana | Platform | grafana.fzymgc.house | Traefik IngressRoute | OIDC |
| ArgoCD | Platform | argocd.fzymgc.house | Helm Managed | OIDC |
| Windmill | Platform | windmill.fzymgc.house | Traefik IngressRoute | OIDC |
| Prometheus | Platform | prometheus.fzymgc.house | Traefik IngressRoute | Forward-Auth |
| Mealie | Application | mealie.fzymgc.house | Traefik IngressRoute | OIDC |
| CloudNativePG | Infrastructure | pg-main.fzymgc.house | TCP Passthrough | Certificate |
| Traefik Dashboard | Infrastructure | traefik.k8s.fzymgc.house | Traefik IngressRoute | None |
| Longhorn Dashboard | Infrastructure | longhorn.fzymgc.house | Traefik IngressRoute | None |
| Argo Workflows | Platform | argo-workflows.fzymgc.house | Helm Managed | OIDC |
| NAS | External | nas.fzymgc.house | External | LDAP |
| Teleport | External | teleport.fzymgc.house | External | None |
| Windmill Webhooks | Platform | windmill-wh.fzymgc.net | Cloudflare Tunnel | None |
| Cloudflared | Infrastructure | - | None | None |
| Loki | Platform | - | None | None |
| Alloy | Platform | - | None | None |
| Velero | Infrastructure | - | None | None |
| cert-manager | Infrastructure | - | None | None |
| MetalLB | Infrastructure | - | None | None |
| Valkey | Infrastructure | - | None | None |
| External Secrets | Infrastructure | - | None | None |
| ARC Runners | Platform | - | None | None |
| Grafana Operator | Platform | - | None | None |
| System Upgrade Controller | Infrastructure | - | None | None |
| Kubernetes Replicator | Infrastructure | - | None | None |
| Shared Resources | Infrastructure | - | None | None |
| System Dashboards | Platform | - | None | None |

> **Note:** Services with `-` for hostname and `None` for ingress/auth are cluster-internal components without external endpoints. They're included for completeness and to track operational status.

### 3. Tech References Database

**Purpose:** Official documentation links for all technologies used in the cluster

| Property | Type | Description |
|----------|------|-------------|
| Technology | Title | Technology name |
| Category | Select | Kubernetes, Networking, Storage, Security, Observability, GitOps, Infrastructure, Applications |
| Docs URL | URL | Primary documentation |
| API Reference | URL | API or SDK documentation |
| GitHub | URL | Source repository |
| Version | Text | Current version in cluster |
| Notes | Text | Additional context |

**Categories and Technologies (28 total):**

| Category | Technologies |
|----------|--------------|
| Kubernetes | k3s, Helm, Gateway API |
| Networking | Calico, MetalLB, Traefik, kube-vip, Cloudflare Tunnel |
| Storage | Longhorn, CloudNativePG, Valkey |
| Security | HashiCorp Vault, External Secrets Operator, cert-manager, Authentik, Teleport |
| Observability | Grafana, Grafana Operator, VictoriaMetrics, Prometheus, Loki, Alloy |
| GitOps | ArgoCD, Argo Workflows, Windmill |
| Infrastructure | Terraform, Ansible, Armbian, Velero, System Upgrade Controller |
| Applications | Mealie |

### 4. Operations Guide Pages

Convert CLAUDE.md files into readable Notion pages:

| Page | Source | Content |
|------|--------|---------|
| Ansible Operations | ansible/CLAUDE.md | Roles, playbook phases, node groups |
| Terraform Modules | tf/CLAUDE.md | Module structure, patterns, commands |
| ArgoCD/GitOps | argocd/CLAUDE.md | Application configs, ExternalSecrets |

### 5. Design Plans Database

**Purpose:** Track implementation decisions and their status

| Property | Type | Description |
|----------|------|-------------|
| Title | Title | Plan name |
| Date | Date | Creation date |
| Status | Status | Active, Completed, Archived |
| Category | Select | Infrastructure, Application, Security, Documentation |
| File Path | Text | Link to repo file |

**Scope:** Only active plans (5); link to archive directory for historical reference.

### 6. Quick Reference Page

Consolidated reference for common operations:

- **Network Configuration**
  - Pod CIDR: `10.42.0.0/16`
  - Service CIDR: `10.43.0.0/16`
  - K8s API VIP: `192.168.20.140`
  - MetalLB Pools: `192.168.20.145-149`, `192.168.20.155-159`
  - Cluster DNS: `10.43.0.10`

- **Common Commands**
  - Environment setup
  - Ansible playbook execution
  - Terraform operations
  - Kubectl context

- **Vault Paths**
  - Authentik: `secret/fzymgc-house/cluster/authentik`
  - BMC credentials: `secret/fzymgc-house/infrastructure/bmc/*`
  - Cloudflare tunnel: `secret/fzymgc-house/cluster/cloudflared/tunnels/*`

## Structure Diagram

```
Home Lab (root)
├── Overview (embedded from this page)
│   └── Architecture diagrams
├── Services Catalog (database)
│   └── 29 service entries
├── Tech References (database)
│   └── 28 technology entries
├── Operations Guide
│   ├── Ansible Operations
│   ├── Terraform Modules
│   └── ArgoCD/GitOps
├── Design Plans (database)
│   └── 5 active plans
└── Quick Reference
    ├── Network Configuration
    ├── Common Commands
    └── Vault Paths
```

## AI/Agent Considerations

**Structured data for agent consumption:**
1. **Services Database** - Agents can query by hostname, category, or auth method
2. **Tech References** - Agents can lookup official docs for any technology
3. **Consistent naming** - Properties use clear, predictable names
4. **Status tracking** - Agents can check operational status
5. **Cross-references** - Vault paths link secrets to services

**Example agent queries:**
- "What services use OIDC authentication?" → Filter Services by Auth Method
- "What's the hostname for Grafana?" → Lookup Services by Name
- "Which services are in the windmill namespace?" → Filter by Namespace
- "Where's the Vault documentation?" → Lookup Tech References by Technology
- "What networking technologies are used?" → Filter Tech References by Category

## Implementation Order

1. Create Services Catalog database first (most structured, immediate value)
2. Create Tech References database (official docs for all technologies)
3. Create Quick Reference page (consolidates critical info)
4. Create Operations Guide pages (converts existing docs)
5. Create Design Plans database (links to repo)
6. Update Home Lab overview with links and diagrams

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)
