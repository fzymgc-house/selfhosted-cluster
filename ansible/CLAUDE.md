# CLAUDE.md - Ansible Directory

This file provides guidance to Claude Code when working with Ansible code in this directory.

## File Headers

Always include these headers in playbooks and role files:
```yaml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
```

## Module Usage Standards

### Always Use Fully Qualified Collection Names (FQCN)
```yaml
# Good
ansible.builtin.apt:
ansible.builtin.file:
ansible.builtin.template:
ansible.builtin.systemd:

# Bad
apt:
file:
template:
systemd:
```

## Variable Naming Conventions

- Use snake_case for all variables: `node_network_interface`
- Prefix role variables with role name: `k3sup_version`, `k3sup_config_file`
- Boolean variables should be questions: `enable_monitoring`, `use_external_database`

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

## Security Best Practices

### Vault Usage
```yaml
# Encrypt sensitive variables
ansible-vault encrypt_string 'secret-value' --name 'variable_name'

# Use no_log for sensitive tasks
- name: Set password
  ansible.builtin.user:
    name: username
    password: "{{ vault_password }}"
  no_log: true
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
