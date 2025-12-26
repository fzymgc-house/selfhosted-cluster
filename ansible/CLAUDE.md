# CLAUDE.md - Ansible Directory

Guidance for Claude Code when working with Ansible code in this directory.

**See also:**
- `../CLAUDE.md` - Repository overview, workflow, MCP/skill guidance
- `../tf/CLAUDE.md` - Vault policies when adding new secret paths

## Roles Inventory

| Role | Purpose | Target Hosts |
|------|---------|--------------|
| `k3s-server` | Control plane node installation | `tp_cluster_controlplane` |
| `k3s-agent` | Worker node installation | `tp_cluster_workers` |
| `k3s-common` | Shared k3s configuration | All k3s nodes |
| `k3s-storage` | Storage preparation (partitioning, formatting) | All cluster nodes |
| `kube-vip` | VIP for API endpoint HA (ARP mode, static pod) | `tp_cluster_controlplane` |
| `calico` | Calico CNI installation | First control plane node |
| `longhorn-disks` | Additional storage disk configuration | Nodes with `longhorn_additional_disks` defined |
| `tp2-bootstrap-node` | OS configuration, networking, security | All TuringPi 2 nodes |
| `router-hosts` | router-hosts gRPC server with Vault mTLS | `router` |

## k3s-playbook.yml Execution Phases

The k3s deployment follows a strict phase order:

| Phase | Description | Tags |
|-------|-------------|------|
| 1 | First control plane node initializes cluster, fetches join token | `k3s-server`, `k3s-install`, `k3s-token`, `k3s-kubeconfig` |
| 2 | Additional control plane nodes join (serial: 1) | `k3s-server`, `k3s-install` |
| 3 | kube-vip deployed for API endpoint HA | `kube-vip` |
| 4 | Worker nodes join cluster | `k3s-agent`, `k3s-install` |
| 5 | Calico CNI installed | `k3s-calico`, `calico` |
| 6 | CSI snapshot controller installed | `k3s-csi-snapshot-controller` |
| 7 | Additional Longhorn disks configured | `longhorn-disks` |
| 8 | Longhorn disk configuration registered | `longhorn-disks`, `longhorn-register` |

**Run specific phases:**
```bash
ansible-playbook -i inventory/hosts.yml k3s-playbook.yml --tags kube-vip
ansible-playbook -i inventory/hosts.yml k3s-playbook.yml --tags longhorn-disks
```

## Hardware and Node Groups

### TuringPi 2 Cluster

Two TuringPi 2 boards (alpha/beta), each with 4 compute slots:

| Group | Nodes | Hardware | Role |
|-------|-------|----------|------|
| `tp_cluster_controlplane` | `tpi-alpha-1`, `tpi-alpha-2`, `tpi-alpha-3` | RK1 | Control plane |
| `tp_cluster_workers` | `tpi-alpha-4`, `tpi-beta-[1:4]` | RK1 | Workers |
| `tp_cluster_nodes` | All 8 nodes | RK1 | All cluster nodes |
| `tpi_bmc_hosts` | `tpi-alpha-bmc`, `tpi-beta-bmc` | BMC | Board management |

### Network Configuration

- **Node subnet**: `192.168.20.0/24`
- **Control plane IPs**: `192.168.20.141-143`
- **Worker IPs**: `192.168.20.144`, `192.168.20.151-154`
- **kube-vip VIP**: `192.168.20.140` (API endpoint)
- **Primary interface**: `end0` (Armbian naming on RK1)

## Code Standards

### File Headers

**MUST** include these headers in all playbooks and role files:
```yaml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
```

### Fully Qualified Collection Names (FQCN)

**MUST** use FQCN for all modules:
```yaml
# Correct
ansible.builtin.apt:
ansible.builtin.file:
ansible.builtin.template:

# Wrong - MUST NOT use short names
apt:
file:
template:
```

### Variable Naming

- **MUST** use snake_case: `node_network_interface`
- **SHOULD** prefix role variables with role name: `kube_vip_address`, `calico_version`
- **SHOULD** name boolean variables as questions: `enable_monitoring`, `use_external_database`

## Common Task Patterns

### Package Management
```yaml
- name: Install packages
  ansible.builtin.apt:
    name: "{{ packages }}"
    state: present
    update_cache: true
    cache_valid_time: 3600
```

### Service Management
```yaml
- name: Restart service
  ansible.builtin.systemd:
    name: service-name
    state: restarted
    enabled: true
    daemon_reload: true
```

### File Operations
```yaml
- name: Create config from template
  ansible.builtin.template:
    src: config.yaml.j2
    dest: /etc/app/config.yaml
    owner: root
    group: root
    mode: '0644'
    backup: true
  notify: restart service
```

## Testing Commands

```bash
# Syntax check
ansible-playbook -i inventory/hosts.yml playbook.yml --syntax-check

# Dry run with diff
ansible-playbook -i inventory/hosts.yml playbook.yml --check --diff

# Run specific tags
ansible-playbook -i inventory/hosts.yml k3s-playbook.yml --tags k8s-longhorn

# Limit to specific hosts
ansible-playbook -i inventory/hosts.yml playbook.yml --limit hostname
```

## Security

### Sensitive Data

- **MUST** use `no_log: true` for tasks handling passwords, tokens, or secrets
- **MUST NOT** hardcode secrets in playbooks or variable files
- **SHOULD** use HashiCorp Vault lookups for secrets (see `community.hashi_vault.vault_kv2_get`)

```yaml
- name: Set password
  ansible.builtin.user:
    name: username
    password: "{{ vault_password }}"
  no_log: true  # REQUIRED for sensitive data
```

## Error Handling

### Block/Rescue/Always Pattern
```yaml
- name: Complex operation
  block:
    - name: Try this task
      ansible.builtin.command: /usr/bin/risky-operation

  rescue:
    - name: Handle failure
      ansible.builtin.debug:
        msg: "Operation failed, performing cleanup"

  always:
    - name: Always run this
      ansible.builtin.file:
        path: /tmp/lockfile
        state: absent
```

## Idempotency

### Changed When
```yaml
- name: Check if already configured
  ansible.builtin.command: grep -q "config-line" /etc/config
  register: config_check
  failed_when: false
  changed_when: false

- name: Configure only if needed
  ansible.builtin.lineinfile:
    path: /etc/config
    line: "config-line"
  when: config_check.rc != 0
```

## Performance Optimization

### Async for Long Tasks
```yaml
- name: Long running task
  ansible.builtin.command: /usr/bin/slow-operation
  async: 3600
  poll: 0
  register: slow_job

- name: Check async task
  ansible.builtin.async_status:
    jid: "{{ slow_job.ansible_job_id }}"
  register: job_result
  until: job_result.finished
  retries: 100
  delay: 30
```

## Role Structure

When creating new roles, follow this structure:
```
roles/role-name/
├── defaults/main.yml    # Default variables (lowest precedence)
├── tasks/main.yml       # Main task entry point
├── handlers/main.yml    # Handler definitions
├── templates/           # Jinja2 templates
├── files/              # Static files
├── vars/main.yml       # Role variables (high precedence)
└── meta/main.yml       # Role metadata
```

## Common Patterns for This Cluster

### Wait for Service
```yaml
- name: Wait for service to be ready
  ansible.builtin.wait_for:
    host: "{{ service_host }}"
    port: "{{ service_port }}"
    delay: 10
    timeout: 300
    state: started
```

### Conditional OS-Specific Tasks
```yaml
- name: Include OS-specific tasks
  ansible.builtin.include_tasks: "{{ ansible_os_family }}.yml"
  when: ansible_os_family in ['Debian', 'RedHat']
```

## k3s Playbook Testing

### Pre-Deployment Checklist

**MUST** complete before running k3s playbook on production:

1. **MUST** create a Velero backup:
   ```bash
   velero backup create pre-deploy-$(date +%Y%m%d-%H%M%S) --wait
   ```

2. **MUST** syntax check:
   ```bash
   ansible-playbook -i inventory/hosts.yml k3s-playbook.yml --syntax-check
   ```

3. **SHOULD** dry run on a single node first:
   ```bash
   ansible-playbook -i inventory/hosts.yml k3s-playbook.yml --check --diff --limit tpi-alpha-1
   ```

### Testing Scenarios

#### Fresh Install
- Run playbook against nodes with no k3s installation
- Verify all nodes register and become Ready
- Confirm Calico CNI is operational

#### In-Place Update (No Changes)
- Run playbook against existing cluster
- Verify no changes are made (idempotent)
- Confirm all services remain running

#### Version Upgrade
- Update `k3s_version` variable or let cluster propagate version
- Run playbook
- Verify nodes upgrade sequentially without service disruption

#### Failed Node Recovery
- Uninstall k3s from a worker node
- Run playbook to reinstall
- Verify node rejoins cluster with correct version

### Post-Deployment Verification

```bash
# Check all nodes are Ready
kubectl --context fzymgc-house get nodes

# Verify k3s versions match
kubectl --context fzymgc-house get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.kubeletVersion}{"\n"}{end}'

# Check Calico is healthy
kubectl --context fzymgc-house get pods -n calico-system

# Verify CSI snapshot controller
kubectl --context fzymgc-house get pods -n kube-system -l app=snapshot-controller
```
