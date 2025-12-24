# CLAUDE.md

Guidance for Claude Code when working with this repository.

## Repository Overview

Self-hosted Kubernetes cluster on TuringPi 2 hardware (RK1 compute modules). Three-layer architecture:

| Layer | Location | Purpose |
|-------|----------|---------|
| Ansible | `ansible/` | Cluster deployment, node configuration, k3s installation |
| Terraform | `tf/` | Infrastructure configuration (Vault, Authentik, Grafana) |
| Kubernetes | `argocd/` | Application manifests, managed by ArgoCD |

**Stack:** k3s + Calico CNI, Vault (secrets), Authentik (SSO), Grafana + VictoriaMetrics (observability)

## AI Assistant Guidance

### MCP Servers

| Server | Use For |
|--------|---------|
| Filesystem | **MUST** use for ALL file read/edit operations (prefer over heredocs, shell-based file ops) |
| Serena | Semantic code operations (symbol finding, refactoring) |
| Context7 | Up-to-date library/framework documentation |
| Firecrawl | Web scraping and search (fastest, most reliable) |
| Exa | Deep research, company research, code context |
| Notion | Workspace documentation (Services Catalog, Tech References, Operations Guide) |

### Skills (Check Before Every Task)

| Skill | When to Use |
|-------|-------------|
| `superpowers:brainstorming` | Before creative work, new features, or design decisions |
| `superpowers:systematic-debugging` | When encountering bugs, test failures, or unexpected behavior |
| `superpowers:writing-plans` | Multi-step implementation tasks |
| `superpowers:using-git-worktrees` | Feature work needing isolation |
| `pr-review-toolkit:review-pr` | When asked to "request a review" (NOT `gh pr edit --add-reviewer`) |
| `commit-commands:commit` | Creating git commits |

### Workflow Directives

- **MUST** use feature branches; **MUST NOT** commit directly to `main`
- **MUST** check for applicable skills before responding (even 1% chance → invoke skill)
- **SHOULD** use Filesystem MCP for file operations
- **MUST NOT** apply kubectl changes directly (ArgoCD manages deployments)
- **MUST NOT** delete the `windmill-staging` branch
- **MUST** update Notion documentation when changes affect services, technologies, or operations (see below)

## Development Workflow

### Environment Setup
```bash
./setup-venv.sh              # One-time
source .venv/bin/activate    # Before Ansible work
export VAULT_ADDR=https://vault.fzymgc.house && vault login
./scripts/vault-helper.sh status  # Check Vault connectivity
```

### Branch Workflow
```bash
git checkout -b feat/description   # Create feature branch
# Make changes, commit
gh pr create --title "feat: Description" --body "..."
# ArgoCD syncs after merge to main
```

### Deployment Stages
1. **Ansible**: Deploy k3s cluster (`ansible/k3s-playbook.yml`)
2. **Terraform**: Bootstrap infrastructure (`tf/cluster-bootstrap`)
3. **ArgoCD**: Manages all application deployments (GitOps)
4. **Windmill**: Terraform automation flows (`windmill/f/terraform/`) - see `docs/windmill-migration.md`

## Quick Reference

### Network
- **K8s API VIP**: `192.168.20.140` (kube-vip)
- **Cluster CIDR**: `10.42.0.0/16` (pods), `10.43.0.0/16` (services)
- **MetalLB**: `192.168.20.145-149`, `192.168.20.155-159`

### URLs
- Vault: `https://vault.fzymgc.house`
- Authentik: `https://auth.fzymgc.house` (API: `https://api.goauthentik.io`)
- Grafana: `https://grafana.fzymgc.house`

### Common Commands
```bash
kubectl --context fzymgc-house get nodes
ansible-playbook -i ansible/inventory/hosts.yml ansible/k3s-playbook.yml --check --diff
terraform -chdir=tf/vault plan
```

## Context-Specific Instructions

**MUST** read the relevant subdirectory CLAUDE.md before working in that directory:

### `ansible/CLAUDE.md`
**Read when:** Modifying playbooks, roles, or inventory files
- Roles inventory (k3s-server, k3s-agent, kube-vip, calico, longhorn-disks, etc.)
- k3s-playbook.yml 8-phase execution order with tags
- Hardware node groups (tp_cluster_controlplane, tp_cluster_workers, etc.)
- FQCN requirements, variable naming, security patterns

### `tf/CLAUDE.md`
**Read when:** Modifying Terraform modules or Vault policies
- Module structure (versions.tf, terraform.tf, variables.tf, etc.)
- All modules: cluster-bootstrap, vault, authentik, grafana, cloudflare, teleport, core-services
- Resource naming (underscore_separated), Vault policy patterns
- Provider version constraints (vary by module)

### `argocd/CLAUDE.md`
**Read when:** Modifying Kubernetes manifests or application configs
- Application directory structure and kustomization patterns
- ExternalSecret integration with Vault ClusterSecretStore
- Naming conventions (kebab-case), RBAC scoping
- GitOps workflow (changes sync via ArgoCD after merge)

## Security

- **MUST NOT** commit secrets to Git (use Vault or SOPS)
- **MUST** update Vault policies when adding new secret paths
- **SHOULD** scope RBAC to namespace level
- Authentik token: `secret/fzymgc-house/cluster/authentik` → key: `terraform_token`
- BMC credentials: `secret/fzymgc-house/infrastructure/bmc/*` (Vault-managed)

## Hardware

Two TuringPi 2 boards (alpha/beta), 8 compute nodes total:
- **Control plane**: `tpi-alpha-[1:3]` (RK1)
- **Workers**: `tpi-alpha-4`, `tpi-beta-[1:4]` (RK1)
- **OS**: Armbian 25.08, systemd-networkd
- **Interface**: `end0` (Armbian naming)

## Notion Documentation

**MUST** keep Notion documentation synchronized with repository changes. The Notion workspace provides human-readable and AI-consumable documentation.

**Root Page:** [Home Lab](https://www.notion.so/Home-Lab-17027a0ad6888053b8cbf2584d07c33c)

### Databases to Update

| Database | Update When |
|----------|-------------|
| **Services Catalog** | Adding/removing services, changing hostnames, updating ingress or auth methods |
| **Tech References** | Adding new technologies, updating versions, changing documentation URLs |
| **Design Plans** | Creating new design documents in `docs/plans/` |

### Services Catalog Fields

When adding a new service, populate these fields:
- **Name**: Service name
- **Category**: Platform, Application, Infrastructure, or External
- **Hostname**: Primary DNS name (e.g., `vault.fzymgc.house`)
- **Alt Hostnames**: Alternative DNS entries (if applicable)
- **Ingress Type**: Traefik IngressRoute, TCP Passthrough, Helm Managed, kube-vip VIP, Cloudflare Tunnel, or External
- **Auth Method**: OIDC, Forward-Auth, Certificate, LDAP, or None
- **Vault Path**: Secret location (e.g., `secret/fzymgc-house/cluster/authentik`)
- **Namespace**: Kubernetes namespace
- **Status**: Operational, Degraded, or Maintenance

### Tech References Fields

When adding a new technology, populate these fields:
- **Technology**: Name of the technology
- **Category**: Kubernetes, Networking, Storage, Security, Observability, GitOps, Infrastructure, or Applications
- **Docs URL**: Primary documentation link
- **Version**: Current version in cluster (if applicable)

### Update Triggers

| Change Type | Action Required |
|-------------|-----------------|
| New service deployed | Add entry to Services Catalog |
| Service removed | Update or remove Services Catalog entry |
| DNS/hostname changed | Update Services Catalog hostname |
| New technology adopted | Add entry to Tech References |
| Version upgraded | Update Tech References version |
| Operations docs changed | Update relevant Operations Guide page |
| New design document created | Add entry to Design Plans database |

### Notion Page IDs

| Page/Database | ID |
|---------------|-----|
| Home Lab (root) | `17027a0a-d688-8053-b8cb-f2584d07c33c` |
| Services Catalog | `50a1adf14f1d4d3fbd78ccc2ca36facc` |
| Tech References | `f7548c57375542b395694ae433ff07a4` |
| Quick Reference | `2d327a0ad688818b9d89c9e00a08bbad` |
| Operations Guide | `2d327a0ad688818a9fb7f14fea22e3d9` |

### Editing Notion Pages (Critical)

**MUST** follow these rules when editing Notion pages via MCP:

1. **NEVER use `replace_content`** on pages with children - it orphans/trashes all child pages and databases
2. **ALWAYS use `replace_content_range`** for targeted updates to preserve parent-child relationships
3. **Use `insert_content_after`** when adding new content without modifying existing content

**Notion-flavored Markdown syntax:**
- Inline page links: `<mention-page url="https://www.notion.so/PAGE_ID">Title</mention-page>`
- Inline database links: `<mention-database url="https://www.notion.so/DB_ID">Title</mention-database>`
- Child page blocks (MOVES the page): `<page url="...">Title</page>`
- Child database blocks (MOVES the database): `<database url="...">Title</database>`

**Verification after edits:**
- Fetch the page to confirm `<ancestor-path>` shows correct parent
- Check that child pages/databases still appear at bottom of content
- Verify mentions resolve (not showing "In Trash")
