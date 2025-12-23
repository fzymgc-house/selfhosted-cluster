# Longhorn Additional Disks - Design Document

**Issue:** #320
**Date:** 2025-12-23
**Status:** Approved

## Summary

Add per-node block device configuration for Longhorn, allowing operators to specify additional SATA SSDs or NVMe drives in Ansible host_vars that get partitioned, formatted as BTRFS, mounted, and registered with Longhorn.

## Configuration Schema

Add to `ansible/inventory/host_vars/<node>.yml`:

```yaml
# Existing fields
host_address: 192.168.20.151
host_btrfs_root_volume: /dev/nvme0n1p1
host_btrfs_subvolume_prefix: ""

# NEW: Additional Longhorn storage disks
longhorn_additional_disks:
  - device: /dev/sda
    name: sata-storage-1
    tags:
      - sata
      - bulk
```

| Field | Required | Description |
|-------|----------|-------------|
| `device` | Yes | Block device path (must be empty/unpartitioned) |
| `name` | Yes | Unique identifier, used in mount path `/data/longhorn-<name>` |
| `tags` | No | Longhorn disk tags for scheduling policies |

Nodes without extra disks omit `longhorn_additional_disks`.

## Implementation

### New Role: `longhorn-disks`

**Location:** `ansible/roles/longhorn-disks/`

**Tasks in order:**

1. **Skip if already configured** - Check if mount is active
2. **Validate disk is empty** - `blkid -p` must return nothing
3. **Create GPT partition table** - Single partition spanning disk
4. **Format as BTRFS** - Create filesystem on partition
5. **Create BTRFS subvolume** - Subvolume named `longhorn`
6. **Create systemd mount unit** - Mount at `/data/longhorn-<name>`
7. **Enable and start mount** - Persist across reboots

**File structure:**

```
ansible/roles/longhorn-disks/
├── defaults/main.yml
├── tasks/main.yml
├── handlers/main.yml
├── meta/main.yml
└── templates/
    └── systemd-mount.j2
```

### Playbook Integration

Add two new phases to `k3s-playbook.yml`:

**Phase 6: Prepare additional disk mounts**

```yaml
- name: Configure additional Longhorn disks
  hosts: tp_cluster_nodes
  become: true
  roles:
    - role: longhorn-disks
      when: longhorn_additional_disks is defined
      tags:
        - longhorn-disks
```

**Phase 7: Register disks with Longhorn**

```yaml
- name: Register Longhorn disk configuration
  hosts: tp_cluster_nodes
  gather_facts: false
  tasks:
    - name: Check if Longhorn is installed
      # ... detection logic

    - name: Patch Longhorn Node CRD (existing cluster)
      # ... direct CRD patch
      when: longhorn_installed

    - name: Set node annotation (fresh cluster)
      # ... annotation for new clusters
      when: not longhorn_installed
```

## Safety Checks

**Strict validation before touching any disk:**

```yaml
- name: Check disk has no partition table
  ansible.builtin.command:
    cmd: blkid -p {{ item.device }}
  register: disk_check
  failed_when: disk_check.rc == 0
  changed_when: false
```

If disk contains any partition table or filesystem, the task fails. User must manually wipe first:

```bash
wipefs -a /dev/sda
```

## Idempotency

| State | Action |
|-------|--------|
| Mount active at `/data/longhorn-<name>` | Skip all steps |
| Partition exists with BTRFS | Create subvolume if missing, mount |
| Disk has data | **FAIL** (safety) |
| Disk empty | Full setup: partition, format, mount |

## Longhorn Registration

### Node Annotation Format

For fresh clusters (Longhorn not yet installed):

```json
[
  {"path":"/data/longhorn","allowScheduling":true},
  {"path":"/data/longhorn-sata-storage-1","allowScheduling":true,"tags":["sata","bulk"]}
]
```

Set via annotation: `node.longhorn.io/default-disks-config`

### Longhorn Node CRD Patch

For existing clusters (Longhorn already running):

```yaml
- name: Patch Longhorn Node CRD
  kubernetes.core.k8s_json_patch:
    kind: Node
    api_version: longhorn.io/v1beta2
    name: "{{ inventory_hostname }}"
    namespace: longhorn-system
    patch:
      - op: add
        path: /spec/disks/{{ item.name }}
        value:
          path: "/data/longhorn-{{ item.name }}"
          allowScheduling: true
          tags: "{{ item.tags | default([]) }}"
```

## Handling Existing Nodes

| Scenario | Method |
|----------|--------|
| New node joining cluster without Longhorn | Set annotation, Terraform reads later |
| New node joining cluster with Longhorn | Patch Longhorn Node CRD |
| Existing node, adding new disk | Patch Longhorn Node CRD |

**Operator workflow for existing nodes:**

1. Physically attach disk
2. Add config to `host_vars/<node>.yml`
3. Run: `ansible-playbook k3s-playbook.yml --tags longhorn-disks --limit <node>`
4. Disk is prepared and registered automatically

## Deployment Order

| Phase | Component | Purpose |
|-------|-----------|---------|
| 1-3 | k3s-storage, k3s-server/agent | Cluster formation |
| 4 | calico | CNI |
| 5 | CSI snapshot | Snapshot controller |
| **6** | **longhorn-disks** | Prepare additional mounts |
| **7** | **Node annotation/CRD patch** | Register with Longhorn |
| Post | Terraform cluster-bootstrap | Install Longhorn (reads annotations) |

## Files Changed

**New:**
- `ansible/roles/longhorn-disks/` - New role

**Modified:**
- `ansible/k3s-playbook.yml` - Add phases 6 and 7
- `ansible/inventory/host_vars/*.yml` - Add disk config where needed

## References

- [Longhorn Node and Disk Configuration](https://longhorn.io/docs/latest/advanced-resources/default-disk-and-node-config/)
- Issue #320
