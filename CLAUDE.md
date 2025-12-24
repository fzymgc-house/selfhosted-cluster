# CLAUDE.md

Guidance for Claude Code when working with this repository.

## Repository Overview

Self-hosted Kubernetes cluster on TuringPi 2 hardware (RK1/Jetson Orin NX). Three-layer architecture:

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

## Development Workflow

### Environment Setup
```bash
./setup-venv.sh              # One-time
source .venv/bin/activate    # Before Ansible work
export VAULT_ADDR=https://vault.fzymgc.house && vault login
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

Subdirectory CLAUDE.md files provide detailed guidance:

| File | Coverage |
|------|----------|
| `ansible/CLAUDE.md` | Roles inventory, k3s playbook phases, FQCN requirements, node groups |
| `tf/CLAUDE.md` | Module structure, Vault policy patterns, provider conventions |
| `argocd/CLAUDE.md` | ExternalSecrets patterns, Kustomization structure, RBAC |

## Security

- **MUST NOT** commit secrets to Git (use Vault or SOPS)
- **MUST** update Vault policies when adding new secret paths
- **SHOULD** scope RBAC to namespace level
- Authentik token: `secret/fzymgc-house/cluster/authentik` → key: `terraform_token`
- BMC credentials: `secret/fzymgc-house/infrastructure/bmc/*` (Vault-managed)

## Hardware

Two TuringPi 2 boards (alpha/beta), 8 compute nodes total:
- **Control plane**: `tpi-alpha-[1:3]` (RK1, 32GB)
- **Workers**: `tpi-alpha-4`, `tpi-beta-[1:4]` (RK1/Jetson mix)
- **OS**: Armbian 25.08, systemd-networkd
- **Interface**: `end0` (Armbian naming)
