# Design: Architecture Diagrams

**Date:** 2025-12-23
**Status:** Draft

## Purpose

Create visual documentation showing how cluster components work together from bootstrap and change management perspectives. Target audience: technical reference for maintainers and README overview for visitors.

## Deliverables

Three draw.io diagrams in `.drawio.svg` format (editable source that renders as SVG):

| File | Purpose |
|------|---------|
| `docs/diagrams/bootstrap-sequence.drawio.svg` | Initial cluster setup flow |
| `docs/diagrams/change-management.drawio.svg` | How changes flow from Git to cluster |
| `docs/diagrams/windmill-terraform-flow.drawio.svg` | Detailed Terraform approval process |

## Diagram 1: Bootstrap Sequence

Shows the linear progression from prepared nodes to a self-managing cluster.

**Scope:**
- Start: Nodes with Armbian configured (networking, packages ready)
- End: ArgoCD running and syncing applications

**Layout:** Left-to-right flow with three swim lanes

| Ansible | Terraform | Handoff |
|---------|-----------|---------|
| k3s-storage (BTRFS mounts) | cert-manager | ArgoCD syncs app-configs |
| k3s-server (first control plane) | External Secrets + Vault auth | ✅ Cluster Operational |
| kube-vip (API HA @ 192.168.20.140) | Longhorn | |
| k3s-server (join additional CP) | MetalLB | |
| k3s-agent (join workers) | ArgoCD | |
| calico (CNI) | | |
| longhorn-disks | | |

**Key points:**
- Ansible phases execute sequentially; first control plane must exist before others join
- kube-vip provides the stable API endpoint for node joins
- Terraform runs from workstation with kubectl access
- ArgoCD is the last bootstrap component; once running, it manages everything else

## Diagram 2: Change Management

Shows three parallel paths for different change types.

**Layout:** Three vertical lanes, all originating from GitHub repository

```
                    GitHub Repository
         ┌──────────────┼──────────────┐
         │              │              │
         ▼              ▼              ▼
    ansible/          tf/         argocd/
         │              │              │
         ▼              ▼              ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│   ANSIBLE   │ │  TERRAFORM  │ │   ARGOCD    │
│ Manual/Rare │ │  Windmill   │ │  Auto-sync  │
├─────────────┤ ├─────────────┤ ├─────────────┤
│ PR merged   │ │ PR merged   │ │ PR merged   │
│ Manual run  │ │ Webhook     │ │ Detected    │
│ Playbook    │ │ Plan+Notify │ │ Auto-sync   │
│ Verify      │ │ Approval    │ │ Applied     │
│ ✅ Complete │ │ Apply       │ │ ✅ Complete │
└─────────────┘ │ ✅ Complete │ └─────────────┘
                └─────────────┘
```

**Key points:**
- Ansible changes are manual and rare (cluster rebuilds, node additions)
- Terraform changes require Discord approval via Windmill
- ArgoCD changes sync automatically on merge
- Terraform lane links to detailed sub-diagram

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

## Visual Style

**Color scheme (consistent across all diagrams):**

| Color | Meaning |
|-------|---------|
| Blue | Ansible/infrastructure |
| Purple | Terraform/Windmill |
| Green | ArgoCD/GitOps/success states |
| Orange | Approval required (attention) |
| Gray | External systems (GitHub, hardware) |
| Discord Blurple (#5865F2) | Discord elements |

**Format:**
- `.drawio.svg` files: editable in draw.io, render as SVG in GitHub
- Store in `docs/diagrams/`
- Embed in README.md with standard markdown image syntax

## README Integration

Add "Architecture" section to README.md:

```markdown
## Architecture

### Bootstrap Sequence
![Bootstrap Sequence](docs/diagrams/bootstrap-sequence.drawio.svg)

### Change Management
![Change Management](docs/diagrams/change-management.drawio.svg)

For detailed Terraform approval workflow, see [Windmill Terraform Flow](docs/diagrams/windmill-terraform-flow.drawio.svg).
```

## Implementation

1. Create `docs/diagrams/` directory
2. Create three `.drawio.svg` files with specified layouts
3. Update README.md with Architecture section
4. Commit and push

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)
