# kube-vip for Kubernetes API Endpoint - Design Document

**Issue:** #319
**Date:** 2025-12-23
**Status:** Approved

## Summary

Add kube-vip for Kubernetes API endpoint high availability, replacing the external HAProxy VIP with a native Kubernetes solution using ARP-based leader election.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    VIP: 192.168.20.140                  │
│                  k8s-cluster.fzymgc.house               │
└─────────────────────┬───────────────────────────────────┘
                      │ ARP (leader owns VIP)
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
   ┌─────────┐   ┌─────────┐   ┌─────────┐
   │ alpha-1 │   │ alpha-2 │   │ alpha-3 │
   │ kube-vip│   │ kube-vip│   │ kube-vip│
   │ (leader)│   │(standby)│   │(standby)│
   └─────────┘   └─────────┘   └─────────┘
```

**Key decisions:**
- **ARP mode** — Flat L2 network, no BGP infrastructure needed
- **Static pod manifest** — Runs before API server, survives API outages
- **New VIP: 192.168.20.140** — On node subnet, avoids routing complexity
- **Parallel migration** — Keep HAProxy active during transition

## Static Pod Manifest

kube-vip runs as a static pod on each control plane node. The kubelet reads manifests from `/var/lib/rancher/k3s/agent/pod-manifests/` and manages the pods directly—no API server needed during bootstrap.

**Manifest structure:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: kube-vip
  namespace: kube-system
spec:
  hostNetwork: true
  containers:
  - name: kube-vip
    image: ghcr.io/kube-vip/kube-vip:v1.0.3
    args:
      - manager
    env:
      - name: vip_arp
        value: "true"
      - name: vip_interface
        value: "end0"
      - name: vip_address
        value: "192.168.20.140"
      - name: vip_leaderelection
        value: "true"
      - name: cp_enable
        value: "true"
      - name: cp_namespace
        value: "kube-system"
    securityContext:
      capabilities:
        add: ["NET_ADMIN", "NET_RAW"]
```

**Key settings:**
- `hostNetwork: true` — Required for ARP announcements
- `vip_leaderelection` — Uses Kubernetes Lease for leader election
- `NET_ADMIN`, `NET_RAW` — Capabilities for ARP manipulation
- `end0` — Primary network interface on RK1 nodes (Armbian naming)

**Note:** Interface must be specified explicitly—kube-vip has no auto-detection.

## Ansible Integration

**New role:** `kube-vip` in `ansible/roles/`

**Role structure:**
```
ansible/roles/kube-vip/
├── defaults/main.yml      # VIP address, interface, version
├── tasks/main.yml         # Deploy static pod manifest
├── templates/
│   └── kube-vip.yaml.j2   # Static pod manifest
└── meta/main.yml
```

**Key variables:**
```yaml
# defaults/main.yml
kube_vip_version: "v1.0.3"
kube_vip_address: "192.168.20.140"
kube_vip_interface: "end0"
kube_vip_image: "ghcr.io/kube-vip/kube-vip:{{ kube_vip_version }}"
```

**Playbook integration:**

Run on control plane nodes only, before k3s server starts:

```yaml
# In k3s-playbook.yml - before k3s-server role
- name: Deploy kube-vip on control plane
  hosts: tpi_alpha_control_plane
  become: true
  roles:
    - role: kube-vip
      tags: [kube-vip]
```

**Task flow:**
1. Create manifest directory (if missing)
2. Template `kube-vip.yaml` to `/var/lib/rancher/k3s/agent/pod-manifests/`
3. kubelet picks it up automatically—no restart needed

**Idempotency:** Template task only changes file if content differs.

## Migration Plan

**Pre-requisite: Add TLS SAN**

The new VIP must be in the API server certificate before kube-vip is useful.

1. Add `192.168.20.140` to `k8s_cluster_sans` in `ansible/inventory/group_vars/tp_cluster_controlplane.yml`
2. Run k3s-server role to regenerate certificates
3. k3s servers will restart to pick up new cert

```yaml
# tp_cluster_controlplane.yml
k8s_cluster_sans:
  - k8s-cluster.fzymgc.house
  - 10.255.254.6
  - 192.168.20.140    # NEW: kube-vip VIP
  - 192.168.20.141
  # ... existing node IPs
```

**Phase 1: Update TLS SANs + Deploy kube-vip**
```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/k3s-playbook.yml \
  --tags k3s-server,kube-vip --limit tpi_alpha_control_plane
```

Verify:
```bash
# Check new SAN in cert
kubectl --context fzymgc-house get secret -n kube-system k3s-serving \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text | grep 192.168.20.140

# Test new VIP
curl -k https://192.168.20.140:6443/healthz
```

**Phase 2: Update DNS** — Point `k8s-cluster.fzymgc.house` to `192.168.20.140`

**Phase 3: Update kubeconfigs** — Local configs to use new VIP

**Phase 4: Decommission HAProxy**
- Remove HAProxy VIP from Firewalla
- Update `calico_can_reach_ip` to `192.168.20.1` (gateway, always reachable)

## Testing & Validation

**Pre-deployment checks:**
```bash
# Verify kube-vip image is pullable
docker pull ghcr.io/kube-vip/kube-vip:v1.0.3

# Confirm 192.168.20.140 is not in use
ping -c 1 192.168.20.140  # Should fail (no response)
```

**Post-deployment validation:**

| Check | Command | Expected |
|-------|---------|----------|
| Pods running | `kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip` | 3 pods, 1 leader |
| VIP responds | `curl -k https://192.168.20.140:6443/healthz` | `ok` |
| Leader election | `kubectl get lease -n kube-system kube-vip-cp` | One holder |
| ARP entry | `arp -n 192.168.20.140` (from another host) | Points to leader node MAC |

**Failover test:**
```bash
# Identify current leader
kubectl get lease -n kube-system kube-vip-cp -o jsonpath='{.spec.holderIdentity}'

# Drain leader node
kubectl drain <leader-node> --ignore-daemonsets --delete-emptydir-data

# Verify VIP moves (within seconds)
curl -k https://192.168.20.140:6443/healthz  # Should still respond

# Uncordon node
kubectl uncordon <leader-node>
```

**Rollback procedure:**

If issues arise, revert DNS to `10.255.254.6` — HAProxy remains active throughout migration.

## Files Changed

**New:**
```
ansible/roles/kube-vip/
├── defaults/main.yml
├── tasks/main.yml
├── templates/kube-vip.yaml.j2
└── meta/main.yml
```

**Modified:**

| File | Change |
|------|--------|
| `ansible/inventory/group_vars/tp_cluster_controlplane.yml` | Add `192.168.20.140` to `k8s_cluster_sans` |
| `ansible/roles/calico/defaults/main.yml` | Update `calico_can_reach_ip` to `192.168.20.1` (Phase 4) |
| `ansible/k3s-playbook.yml` | Add kube-vip role before k3s-server |

**External changes (manual):**
- DNS: Update `k8s-cluster.fzymgc.house` A record
- Firewalla: Remove HAProxy VIP configuration (Phase 4)
- Local kubeconfigs: Update server URL

## References

- [kube-vip Static Pod Installation](https://kube-vip.io/docs/installation/static/)
- [kube-vip ARP Mode](https://kube-vip.io/docs/modes/arp/)
- Issue #319
