# Design: Remove k3sup in Favor of Native Ansible Roles

**Date:** 2025-12-22
**Status:** Completed

## Implementation Summary

All proposed roles have been implemented and the k3sup role has been removed:

| Role | Status |
|------|--------|
| `k3s-common` | ✅ Implemented |
| `k3s-server` | ✅ Implemented |
| `k3s-agent` | ✅ Implemented |
| `k3s-storage` | ✅ Implemented |
| `calico` | ✅ Implemented |
| `kube-vip` | ✅ Implemented (added for API HA) |
| `k3sup` (old) | ✅ Removed |

The k3s-playbook.yml now follows an 8-phase execution order documented in `ansible/CLAUDE.md`.

---

## Motivation

k3sup's "plan mode" now requires payment. We want to manage k3s installation and configuration directly via Ansible without external tool dependencies.

## Current State

The `k3sup` role currently handles:
- k3s server and agent installation via k3sup CLI
- BTRFS subvolume storage setup
- Calico CNI installation
- Multipath/iSCSI configuration for Longhorn
- Docker socket symlink for containerd

## Proposed Architecture

### New Roles

| Role | Purpose |
|------|---------|
| `k3s-common` | Shared k3s configuration templates |
| `k3s-server` | Control plane installation (depends on k3s-common) |
| `k3s-agent` | Worker installation (depends on k3s-common) |
| `k3s-storage` | BTRFS subvolume setup with systemd mounts |
| `calico` | Tigera operator and Calico CRs |

### Modified Roles

| Role | Changes |
|------|---------|
| `tp2-bootstrap-node` | Add multipath, iSCSI, docker socket tasks |

### Deleted

- `k3sup` role (after migration complete and verified)

## Role Details

### k3s-common

Shared configuration installed as a dependency by both k3s-server and k3s-agent.

**Files:**
- `templates/k3s-config.yaml.j2` - k3s configuration
- `templates/registries.yaml.j2` - embedded registry mirrors
- `defaults/main.yml` - default variables

**k3s-config.yaml.j2:**
```yaml
secrets-encryption: true
node-ip: {{ ansible_host }}
node-name: {{ inventory_hostname }}
cluster-cidr: {{ k3s_cluster_cidr | default('10.42.0.0/16') }}
service-cidr: {{ k3s_service_cidr | default('10.43.0.0/16') }}
cluster-dns: {{ k3s_cluster_dns | default('10.43.0.10') }}
cluster-domain: {{ k3s_cluster_domain | default('cluster.local') }}
embedded-registry: true
flannel-backend: none
disable-network-policy: true
disable:
  - traefik
  - servicelb
kube-apiserver-arg:
  - feature-gates=ImageVolume=true
kubelet-arg:
  - feature-gates=ImageVolume=true
{% if k3s_role == 'server' and k3s_is_first_server %}
cluster-init: true
{% elif k3s_role == 'server' %}
server: https://{{ k3s_first_server_ip }}:6443
token: {{ k3s_join_token }}
{% endif %}
{% if k3s_tls_san is defined %}
tls-san:
{% for san in k3s_tls_san %}
  - {{ san }}
{% endfor %}
{% endif %}
```

### k3s-server

Control plane installation using official k3s install script.

**Tasks:**
1. Download k3s install script to `/tmp/k3s-install.sh`
2. Template `/etc/rancher/k3s/config.yaml`
3. Template `/etc/rancher/k3s/registries.yaml`
4. Run install script with `INSTALL_K3S_SKIP_START=true` (if needed for config)
5. Start k3s service
6. Wait for k3s to be ready
7. Fetch join token (first server only)

**Token Handling:**
- First server fetches `/var/lib/rancher/k3s/server/node-token`
- Token propagated to all nodes via `delegate_facts`

### k3s-agent

Worker installation using official k3s install script.

**Tasks:**
1. Download k3s install script
2. Template `/etc/rancher/k3s/config.yaml` (agent config)
3. Run install script with `K3S_URL` set
4. Wait for node to be Ready

### k3s-storage

BTRFS subvolume setup for k3s data directories.

**Tasks:**
1. Get UUID of BTRFS root volume
2. Create BTRFS subvolumes: `rancher`, `kubelet`, `longhorn`
3. Create mount point directories
4. Template systemd mount units
5. Enable and start mount units

**Systemd Mount Template:**
```ini
[Unit]
Description=Mount {{ path }} from btrfs subvolume
Before=local-fs.target
Requires=systemd-modules-load.service

[Mount]
What=UUID={{ uuid }}
Where={{ path }}
Type=btrfs
Options=subvol={{ btrfs_subvolume }},defaults,noatime,compress=zstd

[Install]
WantedBy=multi-user.target
```

**Mounts:**
- `/var/lib/rancher` → `data/rancher` subvolume
- `/var/lib/kubelet` → `data/kubelet` subvolume
- `/var/lib/longhorn` → `data/longhorn` subvolume

### calico

Tigera operator installation with Calico custom resources.

**Tasks:**
1. Install Calico operator CRDs from GitHub (version-pinned)
2. Install Tigera operator from GitHub
3. Create Installation CR with:
   - Node address autodetection on `end0` interface
   - IP pool with cluster CIDR
   - VXLANCrossSubnet encapsulation
4. Create APIServer CR
5. Create Goldmane CR (flow aggregator)
6. Create Whisker CR (observability UI)

**Variables:**
- `calico_version` - Calico version to install
- `k8s_cluster_cidr` - Cluster CIDR for IP pool

### tp2-bootstrap-node Additions

New tasks for Longhorn prerequisites:

**tasks/longhorn-prereqs.yml:**
```yaml
- name: Configure multipath for Longhorn
  ansible.builtin.copy:
    content: |
      defaults {
        user_friendly_names yes
        find_multipaths yes
      }
      blacklist {
        device {
          vendor "IET"
          product "VIRTUAL-DISK"
        }
      }
    dest: /etc/multipath.conf
    mode: "0644"
  notify: Restart multipathd

- name: Enable multipathd
  ansible.builtin.systemd:
    name: multipathd
    state: started
    enabled: true

- name: Enable open-iscsi
  ansible.builtin.systemd:
    name: open-iscsi
    state: started
    enabled: true

- name: Configure docker socket symlink
  ansible.builtin.copy:
    src: docker-sock.conf
    dest: /etc/tmpfiles.d/docker-sock.conf
    mode: "0644"

- name: Create docker socket symlink
  ansible.builtin.command:
    cmd: systemd-tmpfiles --create /etc/tmpfiles.d/docker-sock.conf
  changed_when: true
```

**Note:** Verify no duplication with existing bootstrap role tasks before adding.

## Playbook Structure

```yaml
# k3s-playbook.yml

# Phase 1: First control plane node
- hosts: tp_cluster_controlplane[0]
  become: true
  roles:
    - k3s-storage
    - role: k3s-server
      vars:
        k3s_is_first_server: true
  tasks:
    - name: Fetch join token
      ansible.builtin.slurp:
        src: /var/lib/rancher/k3s/server/node-token
      register: k3s_token_raw

    - name: Set token fact for cluster
      ansible.builtin.set_fact:
        k3s_join_token: "{{ k3s_token_raw.content | b64decode | trim }}"
      delegate_to: "{{ item }}"
      delegate_facts: true
      loop: "{{ groups['tp_cluster_nodes'] }}"

# Phase 2: Additional control plane nodes
- hosts: tp_cluster_controlplane[1:]
  become: true
  roles:
    - k3s-storage
    - role: k3s-server
      vars:
        k3s_is_first_server: false

# Phase 3: Worker nodes
- hosts: tp_cluster_workers
  become: true
  roles:
    - k3s-storage
    - k3s-agent

# Phase 4: CNI installation
- hosts: localhost
  gather_facts: false
  roles:
    - calico
```

## Pre-Implementation Requirements

1. **Velero Backup**
   - Create full cluster backup before starting
   - Verify backup is restorable
   - Document backup name/timestamp

2. **Rollback Procedure**
   - Document steps to restore from Velero backup
   - Keep k3sup role until migration verified

3. **Testing Plan**
   - Test on tpi-beta cluster first (if available)
   - Verify all nodes join successfully
   - Verify Calico networking functions
   - Verify Longhorn storage works
   - Verify existing workloads function

## Migration Steps

1. Create Velero backup
2. Create new roles (k3s-common, k3s-server, k3s-agent, k3s-storage, calico)
3. Update tp2-bootstrap-node with Longhorn prereqs
4. Update k3s-playbook.yml to use new roles
5. Test on non-production cluster
6. Apply to production cluster
7. Verify all functionality
8. Remove k3sup role

## Rollback Plan

If migration fails:
1. Restore from Velero backup
2. Revert playbook changes
3. Re-run with original k3sup role

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)
