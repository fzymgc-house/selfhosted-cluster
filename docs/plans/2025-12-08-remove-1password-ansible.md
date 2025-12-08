# Remove 1Password References from Ansible Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove all 1Password references from the Ansible portion of the codebase by deleting dead code that has been superseded by Terraform bootstrap.

**Architecture:** Pure deletion - the referenced components (ArgoCD, cert-manager, external-secrets, Longhorn, MetalLB, Prometheus CRDs) have been migrated to `tf/cluster-bootstrap`. The Ansible tasks and associated files are now dead code. Two orphaned variables that used 1Password lookups will also be removed.

**Tech Stack:** Ansible, Git

---

## Task 1: Delete Dead Task Files

**Files:**
- Delete: `ansible/roles/k3sup/tasks/argocd.yml`
- Delete: `ansible/roles/k3sup/tasks/cert-manager.yml`
- Delete: `ansible/roles/k3sup/tasks/external-secrets-operator.yml`
- Delete: `ansible/roles/k3sup/tasks/longhorn.yml`
- Delete: `ansible/roles/k3sup/tasks/metallb.yml`
- Delete: `ansible/roles/k3sup/tasks/prometheus-crds.yml`

**Step 1: Delete the dead task files**

```bash
rm ansible/roles/k3sup/tasks/argocd.yml \
   ansible/roles/k3sup/tasks/cert-manager.yml \
   ansible/roles/k3sup/tasks/external-secrets-operator.yml \
   ansible/roles/k3sup/tasks/longhorn.yml \
   ansible/roles/k3sup/tasks/metallb.yml \
   ansible/roles/k3sup/tasks/prometheus-crds.yml
```

**Step 2: Verify deletion**

```bash
ls ansible/roles/k3sup/tasks/
```

Expected: Only these files remain: `calico.yml`, `control-plane.yml`, `main.yml`, `storage.yml`, `worker.yml`

**Step 3: Commit**

```bash
git add -A ansible/roles/k3sup/tasks/
git commit -m "chore(ansible): remove dead task files migrated to tf/cluster-bootstrap

These components are now deployed via Terraform:
- ArgoCD
- cert-manager
- external-secrets-operator
- Longhorn
- MetalLB
- Prometheus CRDs"
```

---

## Task 2: Delete Dead Files Directories

**Files:**
- Delete: `ansible/roles/k3sup/files/cert-manager/` (directory)
- Delete: `ansible/roles/k3sup/files/traefik/` (directory)
- Delete: `ansible/roles/k3sup/files/vault/` (directory)
- Delete: `ansible/roles/k3sup/files/gateway-api-setup/` (directory)

**Step 1: Delete the dead directories**

```bash
rm -rf ansible/roles/k3sup/files/cert-manager \
       ansible/roles/k3sup/files/traefik \
       ansible/roles/k3sup/files/vault \
       ansible/roles/k3sup/files/gateway-api-setup
```

**Step 2: Verify deletion**

```bash
ls ansible/roles/k3sup/files/
```

Expected: Only these items remain: `csi-snapshot-setup/`, `docker-sock.conf`, `k3s-embedded-registries.yaml`

**Step 3: Commit**

```bash
git add -A ansible/roles/k3sup/files/
git commit -m "chore(ansible): remove dead files directories

Removed directories used only by deleted task files:
- cert-manager/
- traefik/
- vault/
- gateway-api-setup/"
```

---

## Task 3: Remove Orphaned 1Password Variable from Controlplane Group Vars

**Files:**
- Modify: `ansible/inventory/group_vars/tp_cluster_controlplane.yml` (remove line 7)

**Context:** The `cloudflare_api_token` variable is defined twice:
1. In `tp_cluster_controlplane.yml` using 1Password lookup (to be removed)
2. In `tp_cluster_nodes.yml` using Vault lookup (already correct)

**Step 1: Edit the file to remove the 1Password lookup**

The file should look like this after editing:

```yaml
k8s_cluster_endpoint_name: k8s-cluster.fzymgc.house
k8s_cluster_endpoint_ip: 10.255.254.6
k8s_cluster_sans: k8s-cluster.fzymgc.house,10.255.254.6,192.168.20.141,192.168.20.142,192.168.20.143,192.168.20.144,192.168.20.151,192.168.20.152,192.168.20.153,192.168.20.154
k8s_context: fzymgc-house
k8s_user_name: fzymgc
```

**Step 2: Verify no 1Password references remain in the file**

```bash
rg "onepassword" ansible/inventory/group_vars/tp_cluster_controlplane.yml
```

Expected: No matches found

**Step 3: Commit**

```bash
git add ansible/inventory/group_vars/tp_cluster_controlplane.yml
git commit -m "chore(ansible): remove duplicate cloudflare_api_token using 1Password

The variable is already defined in tp_cluster_nodes.yml using Vault lookup."
```

---

## Task 4: Remove Orphaned Tailscale Variable

**Files:**
- Modify: `ansible/roles/tp2-bootstrap-node/vars/main.yml` (remove line 4)

**Context:** The `tailscale_auth_key` variable is defined but never used in any task.

**Step 1: Edit the file to remove the unused variable**

The file should look like this after editing:

```yaml
# SPDX-License-Identifier: MIT-0
---
# vars file for tp2-bootstrap-node
packages:
  - apt-transport-https
  - ca-certificates
  - chrony
  - curl
  - dnsutils
  - fish
  - gnupg
  - gnupg-agent
  - ldnsutils
  - lsb-release
  - python3
  - python3-hvac
  - python3-pip
  - python3-venv
  - software-properties-common
  - unattended-upgrades
```

**Step 2: Verify no 1Password references remain**

```bash
rg "onepassword" ansible/roles/tp2-bootstrap-node/
```

Expected: No matches found

**Step 3: Commit**

```bash
git add ansible/roles/tp2-bootstrap-node/vars/main.yml
git commit -m "chore(ansible): remove unused tailscale_auth_key variable

The variable was defined but never referenced in any task."
```

---

## Task 5: Verify No 1Password References Remain in Ansible

**Step 1: Search for any remaining 1Password references**

```bash
rg -i "1password|onepassword" ansible/
```

Expected: No matches found

**Step 2: Verify Ansible syntax is still valid**

```bash
source .venv/bin/activate
ansible-playbook -i ansible/inventory/hosts.yml ansible/k3s-playbook.yml --syntax-check
ansible-playbook -i ansible/inventory/hosts.yml ansible/bootstrap-nodes-playbook.yml --syntax-check
```

Expected: Both commands show "Syntax check passed!"

---

## Task 6: Update Documentation

**Files:**
- Delete: `docs/ansible-vault-cleanup.md` (task is complete)
- Modify: `docs/vault-migration.md` (update to reflect completion)

**Step 1: Delete the ansible-vault-cleanup.md file**

```bash
rm docs/ansible-vault-cleanup.md
```

**Step 2: Update vault-migration.md**

Add this section after the Overview:

```markdown
## Completed Migrations

### Ansible (Completed 2025-12-08)

All 1Password references have been removed from Ansible:
- Dead task files deleted (argocd, cert-manager, external-secrets, longhorn, metallb, prometheus-crds)
- Associated files directories deleted (cert-manager/, traefik/, vault/, gateway-api-setup/)
- Orphaned variables removed (cloudflare_api_token duplicate, tailscale_auth_key)

The only Ansible secret lookup now uses Vault:
- `cloudflare_api_token` in `inventory/group_vars/tp_cluster_nodes.yml`
```

**Step 3: Commit**

```bash
git add docs/
git commit -m "docs: update migration docs to reflect Ansible cleanup completion"
```

---

## Task 7: Final Verification and PR

**Step 1: Run full grep to confirm no 1Password references in Ansible**

```bash
rg -i "1password|onepassword" ansible/
```

Expected: No matches found

**Step 2: Check git status**

```bash
git status
```

Expected: Clean working tree

**Step 3: Push branch and create PR**

```bash
git push -u origin chore/remove-1password-ansible
gh pr create --title "chore(ansible): remove all 1Password references" --body "## Summary

- Remove dead Ansible task files migrated to tf/cluster-bootstrap
- Delete associated files directories
- Remove orphaned 1Password lookup variables
- Update documentation

## Deleted Files
- ansible/roles/k3sup/tasks/{argocd,cert-manager,external-secrets-operator,longhorn,metallb,prometheus-crds}.yml
- ansible/roles/k3sup/files/{cert-manager,traefik,vault,gateway-api-setup}/

## Removed Variables
- cloudflare_api_token from tp_cluster_controlplane.yml (duplicate)
- tailscale_auth_key from tp2-bootstrap-node/vars/main.yml (unused)

## Test Plan
- [x] No 1Password references remain in ansible/
- [x] Ansible syntax check passes
- [x] No functional changes to active code

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```
