# Design: Architecture Diagrams

**Date:** 2025-12-23
**Status:** Completed

## Purpose

Create visual documentation showing how cluster components work together from bootstrap and change management perspectives. Target audience: technical reference for maintainers and README overview for visitors.

## Deliverables

Three Mermaid diagrams embedded directly in README.md:

| Diagram | Purpose |
|---------|---------|
| Bootstrap Sequence | Initial cluster setup flow (flowchart LR) |
| Change Management | How changes flow from Git to cluster (flowchart TD) |
| Windmill Terraform Flow | Detailed approval process (sequenceDiagram, collapsible) |

## Diagram 1: Bootstrap Sequence

Shows the linear progression from prepared nodes to a self-managing cluster.

**Scope:**
- Start: Nodes with Armbian configured (networking, packages ready)
- End: ArgoCD running and syncing applications

**Layout:** Left-to-right flowchart with three subgraphs

| Ansible | Terraform | Handoff |
|---------|-----------|---------|
| k3s-storage (BTRFS mounts) | Prometheus CRDs | ArgoCD syncs app-configs |
| k3s-server (first control plane) | cert-manager | ✅ Cluster Operational |
| k3s-server (join additional CP) | External Secrets + Vault auth | |
| kube-vip (API HA @ 192.168.20.140) | Longhorn | |
| k3s-agent (join workers) | MetalLB | |
| calico (CNI) | ArgoCD | |
| CSI snapshot controller | | |
| longhorn-disks | | |

**Key points:**
- Ansible phases execute sequentially; first control plane must exist before others join
- kube-vip provides the stable API endpoint for node joins
- Terraform runs from workstation with kubectl access
- ArgoCD is the last bootstrap component; once running, it manages everything else

## Diagram 2: Change Management

Shows three parallel paths for different change types.

**Layout:** Top-down flowchart with GitHub at top, three parallel lanes below

**Key points:**
- Ansible changes are manual and rare (cluster rebuilds, node additions)
- Terraform changes require Discord approval via Windmill (highlighted in orange)
- ArgoCD changes sync automatically on merge

## Diagram 3: Windmill Terraform Flow

Sequence diagram showing the full approval cycle.

**Participants:** GitHub → Windmill → Discord → Operator → Cluster

**Sequence:**
1. PR merged to main triggers GitHub webhook
2. Windmill receives webhook, runs `terraform plan`
3. Windmill sends Discord embed with plan summary and buttons:
   - 🔍 Review & Approve (opens Windmill approval page)
   - ⏩ Quick Approve (direct resume URL)
   - ❌ Reject (cancel URL)
   - 📋 Run Details (Windmill run page)
4. Operator clicks approval button
5. Windmill resumes, runs `terraform apply`
6. Windmill posts status update to Discord (success/failure)

**Display:** Collapsible `<details>` section to avoid cluttering the README

## Visual Style

**Color scheme (consistent across all diagrams):**

| Color | Meaning |
|-------|---------|
| Blue (#e3f2fd) | Ansible/infrastructure |
| Purple (#f3e5f5) | Terraform/Windmill |
| Green (#e8f5e9) | ArgoCD/GitOps/success states |
| Orange (#fff3e0) | Approval required (attention) |

## Format Decision

**Mermaid over draw.io because:**
- Renders natively in GitHub markdown
- No external files to maintain
- Version-controlled as text
- Editable directly in any text editor

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)
