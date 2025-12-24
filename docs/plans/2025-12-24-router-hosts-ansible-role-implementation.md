# Router-Hosts Ansible Role Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create an Ansible role to deploy router-hosts server on Firewalla using Docker Compose with Vault Agent for automated mTLS certificate management.

**Architecture:** Two-container Docker Compose deployment (vault-agent + router-hosts) with AppRole authentication. Vault Agent fetches certificates from PKI, router-hosts serves gRPC with mTLS. Ansible fetches AppRole credentials at deploy time.

**Tech Stack:** Ansible 2.14+, Docker Compose, HashiCorp Vault Agent, router-hosts v0.6.0

**Reference:** `docs/plans/2025-12-24-router-hosts-ansible-role-design.md`

---

## Task 1: Create Role Directory Structure

**Files:**
- Create: `ansible/roles/router-hosts/defaults/main.yml`
- Create: `ansible/roles/router-hosts/meta/main.yml`
- Create: `ansible/roles/router-hosts/handlers/main.yml`
- Create: `ansible/roles/router-hosts/tasks/main.yml`

**Step 1: Create directory structure**

```bash
mkdir -p ansible/roles/router-hosts/{defaults,meta,handlers,tasks,templates}
```

**Step 2: Create defaults/main.yml**

```yaml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
---
# defaults file for router-hosts
#
# This role deploys router-hosts server on Firewalla using Docker Compose
# with Vault Agent for automated mTLS certificate management.
#
# router-hosts is a gRPC server for managing DNS host entries.
# https://github.com/fzymgc-house/router-hosts

# Base directory for config, data, and credentials
# External storage on Firewalla persists across firmware updates
router_hosts_base_dir: "/extdata/router-hosts"

# Container images
router_hosts_image: "ghcr.io/fzymgc-house/router-hosts"
router_hosts_version: "v0.6.0"
router_hosts_vault_image: "hashicorp/vault:1.18"

# Vault configuration
router_hosts_vault_addr: "https://vault.fzymgc.house"
router_hosts_vault_pki_path: "fzymgc-house/v1/ica1/v1"
router_hosts_vault_approle_name: "router-hosts-agent"

# Certificate configuration
# Common name for the server certificate
router_hosts_cert_cn: "router-hosts"

# DNS SANs for the server certificate
router_hosts_cert_dns_sans:
  - "localhost"
  - "router.fzymgc.house"
  - "router"
  - "router.local"

# IP SANs for the server certificate
router_hosts_cert_ip_sans:
  - "127.0.0.1"
  - "192.168.20.1"
  - "fddb:f665:73f7:1::1"
  - "fe80::226d:31ff:fe31:715"

# Certificate TTL (30 days)
router_hosts_cert_ttl: "720h"

# gRPC server configuration
router_hosts_grpc_port: 50051

# Container user (pi user on Firewalla)
router_hosts_user: "pi"

# Firewalla-specific paths
# Docker compose location (Firewalla convention)
router_hosts_docker_compose_dir: "/home/pi/.firewalla/run/docker/router-hosts"

# Boot script location (post_main.d for auto-start)
router_hosts_post_main_dir: "/home/pi/.firewalla/config/post_main.d"
```

**Step 3: Create meta/main.yml**

```yaml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
---
galaxy_info:
  author: fzymgc-house
  description: Deploy router-hosts server with Vault Agent mTLS on Firewalla
  license: MIT-0
  min_ansible_version: "2.14"
  platforms:
    - name: Debian
      versions:
        - bullseye

dependencies: []

# Required collections (versions in ansible/requirements.yml)
collections:
  - community.hashi_vault
```

**Step 4: Create handlers/main.yml**

```yaml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
---
# handlers file for router-hosts

- name: Restart router-hosts
  ansible.builtin.systemd:
    name: docker-compose@router-hosts
    state: restarted
  listen: restart router-hosts
```

**Step 5: Create tasks/main.yml (skeleton)**

```yaml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
---
# tasks file for router-hosts
# Deploys router-hosts server with Vault Agent mTLS on Firewalla

- name: Include preflight checks
  ansible.builtin.include_tasks: preflight.yml
  tags:
    - router-hosts
    - router-hosts-preflight

- name: Include Vault credentials setup
  ansible.builtin.include_tasks: vault-credentials.yml
  tags:
    - router-hosts
    - router-hosts-vault

- name: Include directory setup
  ansible.builtin.include_tasks: directories.yml
  tags:
    - router-hosts
    - router-hosts-directories

- name: Include configuration deployment
  ansible.builtin.include_tasks: configure.yml
  tags:
    - router-hosts
    - router-hosts-configure

- name: Include Docker deployment
  ansible.builtin.include_tasks: docker.yml
  tags:
    - router-hosts
    - router-hosts-docker

- name: Include verification
  ansible.builtin.include_tasks: verify.yml
  tags:
    - router-hosts
    - router-hosts-verify
```

**Step 6: Run ansible-lint to verify structure**

Run: `ansible-lint ansible/roles/router-hosts/`
Expected: Pass with no errors (may have warnings about missing task files)

**Step 7: Commit**

```bash
git add ansible/roles/router-hosts/
git commit -m "feat(ansible): add router-hosts role skeleton

- defaults with Vault Agent and Firewalla configuration
- meta with collection dependencies
- handlers for service restart
- main tasks entry point"
```

---

## Task 2: Create Preflight Task File

**Files:**
- Create: `ansible/roles/router-hosts/tasks/preflight.yml`

**Step 1: Create preflight.yml**

```yaml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
---
# Preflight checks for router-hosts deployment

- name: Verify Docker is available
  ansible.builtin.command:
    cmd: docker --version
  register: router_hosts_docker_check
  changed_when: false
  failed_when: router_hosts_docker_check.rc != 0
  tags:
    - router-hosts
    - router-hosts-preflight

- name: Verify Docker daemon is running
  ansible.builtin.command:
    cmd: docker info
  register: router_hosts_docker_info
  changed_when: false
  failed_when: router_hosts_docker_info.rc != 0
  tags:
    - router-hosts
    - router-hosts-preflight

- name: Verify Vault is reachable
  ansible.builtin.uri:
    url: "{{ router_hosts_vault_addr }}/v1/sys/health"
    method: GET
    validate_certs: true
    status_code:
      - 200
      - 429  # Sealed but reachable
      - 472  # Standby node
      - 473  # Performance standby
  register: router_hosts_vault_health
  delegate_to: localhost
  become: false
  tags:
    - router-hosts
    - router-hosts-preflight

- name: Verify external storage mount exists
  ansible.builtin.stat:
    path: /extdata
  register: router_hosts_extdata_stat
  tags:
    - router-hosts
    - router-hosts-preflight

- name: Fail if external storage not mounted
  ansible.builtin.fail:
    msg: |
      External storage /extdata not found.
      Ensure the USB/SD storage is mounted on the Firewalla.
  when: not router_hosts_extdata_stat.stat.exists
  tags:
    - router-hosts
    - router-hosts-preflight
```

**Step 2: Run ansible-lint**

Run: `ansible-lint ansible/roles/router-hosts/tasks/preflight.yml`
Expected: Pass

**Step 3: Commit**

```bash
git add ansible/roles/router-hosts/tasks/preflight.yml
git commit -m "feat(ansible): add router-hosts preflight checks

- Docker availability and daemon status
- Vault reachability check
- External storage mount verification"
```

---

## Task 3: Create Vault Credentials Task File

**Files:**
- Create: `ansible/roles/router-hosts/tasks/vault-credentials.yml`

**Step 1: Create vault-credentials.yml**

```yaml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
---
# Fetch Vault AppRole credentials at deploy time
# Runs on localhost (where Vault token is available) and copies to target

- name: Read AppRole role_id from Vault
  community.hashi_vault.vault_read:
    url: "{{ router_hosts_vault_addr }}"
    path: "auth/approle/role/{{ router_hosts_vault_approle_name }}/role-id"
  register: router_hosts_role_id_result
  delegate_to: localhost
  become: false
  no_log: true
  tags:
    - router-hosts
    - router-hosts-vault

- name: Generate new AppRole secret_id from Vault
  community.hashi_vault.vault_write:
    url: "{{ router_hosts_vault_addr }}"
    path: "auth/approle/role/{{ router_hosts_vault_approle_name }}/secret-id"
  register: router_hosts_secret_id_result
  delegate_to: localhost
  become: false
  no_log: true
  tags:
    - router-hosts
    - router-hosts-vault

- name: Set AppRole facts
  ansible.builtin.set_fact:
    router_hosts_role_id: "{{ router_hosts_role_id_result.data.data.role_id }}"
    router_hosts_secret_id: "{{ router_hosts_secret_id_result.data.data.secret_id }}"
  no_log: true
  tags:
    - router-hosts
    - router-hosts-vault

- name: Verify credentials were retrieved
  ansible.builtin.assert:
    that:
      - router_hosts_role_id | length > 0
      - router_hosts_secret_id | length > 0
    fail_msg: "Failed to retrieve AppRole credentials from Vault"
    quiet: true
  no_log: true
  tags:
    - router-hosts
    - router-hosts-vault
```

**Step 2: Run ansible-lint**

Run: `ansible-lint ansible/roles/router-hosts/tasks/vault-credentials.yml`
Expected: Pass

**Step 3: Commit**

```bash
git add ansible/roles/router-hosts/tasks/vault-credentials.yml
git commit -m "feat(ansible): add router-hosts Vault credentials fetch

- Read role_id from Vault AppRole
- Generate fresh secret_id at deploy time
- Delegate to localhost where Vault token is available"
```

---

## Task 4: Create Directories Task File

**Files:**
- Create: `ansible/roles/router-hosts/tasks/directories.yml`

**Step 1: Create directories.yml**

```yaml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
---
# Create directory structure for router-hosts

- name: Get pi user info
  ansible.builtin.getent:
    database: passwd
    key: "{{ router_hosts_user }}"
  register: router_hosts_user_info
  tags:
    - router-hosts
    - router-hosts-directories

- name: Set user UID/GID facts
  ansible.builtin.set_fact:
    router_hosts_uid: "{{ router_hosts_user_info.ansible_facts.getent_passwd[router_hosts_user][1] }}"
    router_hosts_gid: "{{ router_hosts_user_info.ansible_facts.getent_passwd[router_hosts_user][2] }}"
  tags:
    - router-hosts
    - router-hosts-directories

- name: Create base directory
  ansible.builtin.file:
    path: "{{ router_hosts_base_dir }}"
    state: directory
    owner: "{{ router_hosts_user }}"
    group: "{{ router_hosts_user }}"
    mode: "0755"
  tags:
    - router-hosts
    - router-hosts-directories

- name: Create subdirectories
  ansible.builtin.file:
    path: "{{ router_hosts_base_dir }}/{{ item }}"
    state: directory
    owner: "{{ router_hosts_user }}"
    group: "{{ router_hosts_user }}"
    mode: "0755"
  loop:
    - config
    - data
    - vault-approle
    - scripts
    - certs
  tags:
    - router-hosts
    - router-hosts-directories

- name: Set restrictive permissions on vault-approle directory
  ansible.builtin.file:
    path: "{{ router_hosts_base_dir }}/vault-approle"
    mode: "0700"
  tags:
    - router-hosts
    - router-hosts-directories

- name: Create Docker Compose directory (Firewalla convention)
  ansible.builtin.file:
    path: "{{ router_hosts_docker_compose_dir }}"
    state: directory
    owner: "{{ router_hosts_user }}"
    group: "{{ router_hosts_user }}"
    mode: "0755"
  tags:
    - router-hosts
    - router-hosts-directories

- name: Ensure post_main.d directory exists
  ansible.builtin.file:
    path: "{{ router_hosts_post_main_dir }}"
    state: directory
    owner: "{{ router_hosts_user }}"
    group: "{{ router_hosts_user }}"
    mode: "0755"
  tags:
    - router-hosts
    - router-hosts-directories
```

**Step 2: Run ansible-lint**

Run: `ansible-lint ansible/roles/router-hosts/tasks/directories.yml`
Expected: Pass

**Step 3: Commit**

```bash
git add ansible/roles/router-hosts/tasks/directories.yml
git commit -m "feat(ansible): add router-hosts directory setup

- Base directory structure on /extdata
- Restricted permissions for vault-approle
- Docker Compose and post_main.d directories"
```

---

## Task 5: Create Templates

**Files:**
- Create: `ansible/roles/router-hosts/templates/docker-compose.yml.j2`
- Create: `ansible/roles/router-hosts/templates/vault-agent-config.hcl.j2`
- Create: `ansible/roles/router-hosts/templates/server.toml.j2`
- Create: `ansible/roles/router-hosts/templates/on-hosts-update.sh.j2`
- Create: `ansible/roles/router-hosts/templates/z0100-start-router-hosts.sh.j2`

**Step 1: Create docker-compose.yml.j2**

```jinja2
# {{ ansible_managed }}
# Docker Compose for router-hosts with Vault Agent mTLS
---
services:
  vault-agent:
    image: {{ router_hosts_vault_image }}
    container_name: router-hosts-vault-agent
    restart: unless-stopped
    user: "{{ router_hosts_uid }}:{{ router_hosts_gid }}"
    command:
      - agent
      - -config=/vault/config/vault-agent.hcl
    environment:
      VAULT_ADDR: "{{ router_hosts_vault_addr }}"
      VAULT_CACERT: /etc/ssl/certs/ca-certificates.crt
    volumes:
      - {{ router_hosts_base_dir }}/vault-approle:/vault/approle:ro
      - {{ router_hosts_base_dir }}/config/vault-agent.hcl:/vault/config/vault-agent.hcl:ro
      - {{ router_hosts_base_dir }}/certs:/vault/certs:rw
      - /etc/ssl/certs:/etc/ssl/certs:ro
    healthcheck:
      test: ["CMD", "test", "-f", "/vault/certs/server.crt"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  router-hosts:
    image: {{ router_hosts_image }}:{{ router_hosts_version }}
    container_name: router-hosts-server
    restart: unless-stopped
    user: "{{ router_hosts_uid }}:{{ router_hosts_gid }}"
    depends_on:
      vault-agent:
        condition: service_healthy
    ports:
      - "{{ router_hosts_grpc_port }}:{{ router_hosts_grpc_port }}"
    environment:
      RUST_LOG: info
    volumes:
      - {{ router_hosts_base_dir }}/config/server.toml:/config/server.toml:ro
      - {{ router_hosts_base_dir }}/data:/data:rw
      - {{ router_hosts_base_dir }}/certs:/certs:ro
      - {{ router_hosts_base_dir }}/scripts:/scripts:ro
    command:
      - server
      - --config=/config/server.toml
    healthcheck:
      test: ["CMD", "test", "-f", "/data/hosts"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
```

**Step 2: Create vault-agent-config.hcl.j2**

```jinja2
# {{ ansible_managed }}
# Vault Agent configuration for router-hosts mTLS certificates

vault {
  address = "{{ router_hosts_vault_addr }}"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path   = "/vault/approle/role_id"
      secret_id_file_path = "/vault/approle/secret_id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "/vault/certs/.vault-token"
      mode = 0600
    }
  }
}

template_config {
  static_secret_render_interval = "5m"
}

template {
  contents = <<-EOF
  {{ '{{' }}- with pkiCert "{{ router_hosts_vault_pki_path }}/issue/server" "common_name={{ router_hosts_cert_cn }}" "ttl={{ router_hosts_cert_ttl }}" "alt_names={{ router_hosts_cert_dns_sans | join(',') }}" "ip_sans={{ router_hosts_cert_ip_sans | join(',') }}" -{{ '}}' }}
  {{ '{{' }} .Cert {{ '}}' }}
  {{ '{{' }}- end {{ '}}' }}
  EOF
  destination = "/vault/certs/server.crt"
  perms = 0644
}

template {
  contents = <<-EOF
  {{ '{{' }}- with pkiCert "{{ router_hosts_vault_pki_path }}/issue/server" "common_name={{ router_hosts_cert_cn }}" "ttl={{ router_hosts_cert_ttl }}" "alt_names={{ router_hosts_cert_dns_sans | join(',') }}" "ip_sans={{ router_hosts_cert_ip_sans | join(',') }}" -{{ '}}' }}
  {{ '{{' }} .Key {{ '}}' }}
  {{ '{{' }}- end {{ '}}' }}
  EOF
  destination = "/vault/certs/server.key"
  perms = 0600
}

template {
  contents = <<-EOF
  {{ '{{' }}- with pkiCert "{{ router_hosts_vault_pki_path }}/issue/server" "common_name={{ router_hosts_cert_cn }}" "ttl={{ router_hosts_cert_ttl }}" "alt_names={{ router_hosts_cert_dns_sans | join(',') }}" "ip_sans={{ router_hosts_cert_ip_sans | join(',') }}" -{{ '}}' }}
  {{ '{{' }} .CA {{ '}}' }}
  {{ '{{' }}- end {{ '}}' }}
  EOF
  destination = "/vault/certs/ca.crt"
  perms = 0644
  # Use share_dependencies to ensure all cert files are written atomically
  # when any template is rendered (they share the pkiCert call)
}
```

**Step 3: Create server.toml.j2**

```jinja2
# {{ ansible_managed }}
# router-hosts server configuration

[server]
listen_addr = "0.0.0.0:{{ router_hosts_grpc_port }}"

[tls]
cert_path = "/certs/server.crt"
key_path = "/certs/server.key"
ca_path = "/certs/ca.crt"
require_client_cert = true

[storage]
db_path = "/data/router-hosts.db"
hosts_file_path = "/data/hosts"

[hooks]
on_update = "/scripts/on-hosts-update.sh"
```

**Step 4: Create on-hosts-update.sh.j2**

```jinja2
#!/usr/bin/env bash
# {{ ansible_managed }}
# Hook script called after hosts file updates
# Currently a no-op that logs; uncomment to restart Firewalla DNS

# TODO: Uncomment to restart Firewalla DNS when ready
# sudo systemctl restart firerouter_dns

logger -t router-hosts "Hosts file updated"
```

**Step 5: Create z0100-start-router-hosts.sh.j2**

```jinja2
#!/usr/bin/env bash
# {{ ansible_managed }}
# Boot script to start router-hosts Docker Compose service
# Placed in post_main.d to run after Firewalla main startup

sudo systemctl enable --now docker-compose@router-hosts
```

**Step 6: Run ansible-lint**

Run: `ansible-lint ansible/roles/router-hosts/templates/`
Expected: Pass (templates themselves aren't linted, but syntax should be valid)

**Step 7: Commit**

```bash
git add ansible/roles/router-hosts/templates/
git commit -m "feat(ansible): add router-hosts templates

- docker-compose.yml.j2: vault-agent + router-hosts containers
- vault-agent-config.hcl.j2: AppRole auth and PKI cert templates
- server.toml.j2: router-hosts server configuration
- on-hosts-update.sh.j2: hook script (currently no-op)
- z0100-start-router-hosts.sh.j2: boot script for post_main.d"
```

---

## Task 6: Create Configure Task File

**Files:**
- Create: `ansible/roles/router-hosts/tasks/configure.yml`

**Step 1: Create configure.yml**

```yaml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
---
# Deploy configuration files for router-hosts

- name: Write AppRole role_id
  ansible.builtin.copy:
    content: "{{ router_hosts_role_id }}"
    dest: "{{ router_hosts_base_dir }}/vault-approle/role_id"
    owner: "{{ router_hosts_user }}"
    group: "{{ router_hosts_user }}"
    mode: "0600"
  no_log: true
  notify: restart router-hosts
  tags:
    - router-hosts
    - router-hosts-configure

- name: Write AppRole secret_id
  ansible.builtin.copy:
    content: "{{ router_hosts_secret_id }}"
    dest: "{{ router_hosts_base_dir }}/vault-approle/secret_id"
    owner: "{{ router_hosts_user }}"
    group: "{{ router_hosts_user }}"
    mode: "0600"
  no_log: true
  notify: restart router-hosts
  tags:
    - router-hosts
    - router-hosts-configure

- name: Deploy Vault Agent configuration
  ansible.builtin.template:
    src: vault-agent-config.hcl.j2
    dest: "{{ router_hosts_base_dir }}/config/vault-agent.hcl"
    owner: "{{ router_hosts_user }}"
    group: "{{ router_hosts_user }}"
    mode: "0644"
  notify: restart router-hosts
  tags:
    - router-hosts
    - router-hosts-configure

- name: Deploy router-hosts server configuration
  ansible.builtin.template:
    src: server.toml.j2
    dest: "{{ router_hosts_base_dir }}/config/server.toml"
    owner: "{{ router_hosts_user }}"
    group: "{{ router_hosts_user }}"
    mode: "0644"
  notify: restart router-hosts
  tags:
    - router-hosts
    - router-hosts-configure

- name: Deploy on-hosts-update hook script
  ansible.builtin.template:
    src: on-hosts-update.sh.j2
    dest: "{{ router_hosts_base_dir }}/scripts/on-hosts-update.sh"
    owner: "{{ router_hosts_user }}"
    group: "{{ router_hosts_user }}"
    mode: "0755"
  tags:
    - router-hosts
    - router-hosts-configure

- name: Deploy Docker Compose file
  ansible.builtin.template:
    src: docker-compose.yml.j2
    dest: "{{ router_hosts_docker_compose_dir }}/docker-compose.yml"
    owner: "{{ router_hosts_user }}"
    group: "{{ router_hosts_user }}"
    mode: "0644"
  notify: restart router-hosts
  tags:
    - router-hosts
    - router-hosts-configure

- name: Deploy boot script
  ansible.builtin.template:
    src: z0100-start-router-hosts.sh.j2
    dest: "{{ router_hosts_post_main_dir }}/z0100-start-router-hosts.sh"
    owner: "{{ router_hosts_user }}"
    group: "{{ router_hosts_user }}"
    mode: "0755"
  tags:
    - router-hosts
    - router-hosts-configure
```

**Step 2: Run ansible-lint**

Run: `ansible-lint ansible/roles/router-hosts/tasks/configure.yml`
Expected: Pass

**Step 3: Commit**

```bash
git add ansible/roles/router-hosts/tasks/configure.yml
git commit -m "feat(ansible): add router-hosts configuration deployment

- AppRole credentials with restricted permissions
- Vault Agent and server configuration
- Docker Compose and boot scripts"
```

---

## Task 7: Create Docker Task File

**Files:**
- Create: `ansible/roles/router-hosts/tasks/docker.yml`

**Step 1: Create docker.yml**

```yaml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
---
# Deploy router-hosts Docker Compose service

- name: Pull Vault Agent image
  ansible.builtin.command:
    cmd: docker pull {{ router_hosts_vault_image }}
  register: router_hosts_vault_pull
  changed_when: "'Pull complete' in router_hosts_vault_pull.stdout or 'Downloaded newer' in router_hosts_vault_pull.stdout"
  tags:
    - router-hosts
    - router-hosts-docker

- name: Pull router-hosts image
  ansible.builtin.command:
    cmd: docker pull {{ router_hosts_image }}:{{ router_hosts_version }}
  register: router_hosts_pull
  changed_when: "'Pull complete' in router_hosts_pull.stdout or 'Downloaded newer' in router_hosts_pull.stdout"
  tags:
    - router-hosts
    - router-hosts-docker

- name: Start Docker Compose service
  ansible.builtin.systemd:
    name: docker-compose@router-hosts
    state: started
    enabled: true
  tags:
    - router-hosts
    - router-hosts-docker
```

**Step 2: Run ansible-lint**

Run: `ansible-lint ansible/roles/router-hosts/tasks/docker.yml`
Expected: Pass

**Step 3: Commit**

```bash
git add ansible/roles/router-hosts/tasks/docker.yml
git commit -m "feat(ansible): add router-hosts Docker deployment

- Pull container images
- Start and enable docker-compose@router-hosts service"
```

---

## Task 8: Create Verify Task File

**Files:**
- Create: `ansible/roles/router-hosts/tasks/verify.yml`

**Step 1: Create verify.yml**

```yaml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
---
# Verify router-hosts deployment

- name: Wait for Vault Agent to generate certificates
  ansible.builtin.wait_for:
    path: "{{ router_hosts_base_dir }}/certs/server.crt"
    state: present
    timeout: 120
  tags:
    - router-hosts
    - router-hosts-verify

- name: Wait for router-hosts container to be running
  ansible.builtin.command:
    cmd: docker ps --filter "name=router-hosts-server" --filter "status=running" --format "{{ '{{' }}.Names{{ '}}' }}"
  register: router_hosts_container_check
  until: router_hosts_container_check.stdout | length > 0
  retries: 12
  delay: 5
  changed_when: false
  tags:
    - router-hosts
    - router-hosts-verify

- name: Wait for gRPC port to be available
  ansible.builtin.wait_for:
    host: 127.0.0.1
    port: "{{ router_hosts_grpc_port }}"
    state: started
    timeout: 60
  tags:
    - router-hosts
    - router-hosts-verify

- name: Check certificate validity
  ansible.builtin.command:
    cmd: openssl x509 -in {{ router_hosts_base_dir }}/certs/server.crt -noout -dates
  register: router_hosts_cert_dates
  changed_when: false
  tags:
    - router-hosts
    - router-hosts-verify

- name: Report deployment status
  ansible.builtin.debug:
    msg: |
      router-hosts deployed successfully on {{ inventory_hostname }}
      gRPC: 0.0.0.0:{{ router_hosts_grpc_port }}
      Certificates: {{ router_hosts_base_dir }}/certs/
      {{ router_hosts_cert_dates.stdout }}
  tags:
    - router-hosts
    - router-hosts-verify
```

**Step 2: Run ansible-lint**

Run: `ansible-lint ansible/roles/router-hosts/tasks/verify.yml`
Expected: Pass

**Step 3: Commit**

```bash
git add ansible/roles/router-hosts/tasks/verify.yml
git commit -m "feat(ansible): add router-hosts verification

- Wait for certificates from Vault Agent
- Container and port availability checks
- Certificate validity report"
```

---

## Task 9: Create Playbook

**Files:**
- Create: `ansible/router-hosts-playbook.yml`

**Step 1: Create router-hosts-playbook.yml**

```yaml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
---
# Deploy router-hosts to Firewalla
#
# Prerequisites:
# - Vault token available (via VAULT_TOKEN or vault login)
# - community.hashi_vault collection installed
#
# Usage:
# ansible-playbook -i inventory/hosts.yml router-hosts-playbook.yml
#
# Dry run:
# ansible-playbook -i inventory/hosts.yml router-hosts-playbook.yml --check --diff

- name: Deploy router-hosts to Firewalla
  hosts: router
  become: true
  gather_facts: true

  pre_tasks:
    - name: Verify target is the router
      ansible.builtin.assert:
        that:
          - inventory_hostname == 'router'
        fail_msg: "This playbook should only run on the 'router' host"
        quiet: true

  roles:
    - router-hosts

  post_tasks:
    - name: Display service status
      ansible.builtin.command:
        cmd: systemctl status docker-compose@router-hosts --no-pager
      register: router_hosts_service_status
      changed_when: false
      failed_when: false

    - name: Show service status
      ansible.builtin.debug:
        var: router_hosts_service_status.stdout_lines
```

**Step 2: Run syntax check**

Run: `ansible-playbook -i ansible/inventory/hosts.yml ansible/router-hosts-playbook.yml --syntax-check`
Expected: Pass

**Step 3: Run ansible-lint**

Run: `ansible-lint ansible/router-hosts-playbook.yml`
Expected: Pass

**Step 4: Commit**

```bash
git add ansible/router-hosts-playbook.yml
git commit -m "feat(ansible): add router-hosts playbook

- Targets router host
- Uses router-hosts role
- Displays service status on completion"
```

---

## Task 10: Final Validation and Documentation

**Files:**
- Modify: `ansible/CLAUDE.md` (update roles inventory)

**Step 1: Run full ansible-lint on role**

Run: `ansible-lint ansible/roles/router-hosts/ ansible/router-hosts-playbook.yml`
Expected: Pass with no errors

**Step 2: Run syntax check**

Run: `ansible-playbook -i ansible/inventory/hosts.yml ansible/router-hosts-playbook.yml --syntax-check`
Expected: Pass

**Step 3: Update ansible/CLAUDE.md roles inventory**

Add to the Roles Inventory table:

```markdown
| `router-hosts` | router-hosts gRPC server with Vault mTLS | `router` |
```

**Step 4: Commit documentation update**

```bash
git add ansible/CLAUDE.md
git commit -m "docs: add router-hosts role to CLAUDE.md inventory"
```

**Step 5: Create PR**

```bash
gh pr create \
  --title "feat(ansible): add router-hosts role for Firewalla deployment" \
  --body "$(cat <<'EOF'
## Summary
- Add router-hosts Ansible role for deploying router-hosts server on Firewalla
- Uses Docker Compose with Vault Agent for automated mTLS certificate management
- Integrates with Firewalla's docker-compose@ systemd template service

## Changes
- New role: `ansible/roles/router-hosts/`
- New playbook: `ansible/router-hosts-playbook.yml`
- Updated: `ansible/CLAUDE.md` (roles inventory)

## Test plan
- [ ] Syntax check: `ansible-playbook --syntax-check`
- [ ] Lint: `ansible-lint ansible/roles/router-hosts/`
- [ ] Dry run against router: `ansible-playbook --check --diff`
- [ ] Full deployment: `ansible-playbook router-hosts-playbook.yml`

## Related
- Design: `docs/plans/2025-12-24-router-hosts-ansible-role-design.md`
- router-hosts repo: https://github.com/fzymgc-house/router-hosts

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Create role skeleton | `defaults/`, `meta/`, `handlers/`, `tasks/main.yml` |
| 2 | Preflight checks | `tasks/preflight.yml` |
| 3 | Vault credentials | `tasks/vault-credentials.yml` |
| 4 | Directory setup | `tasks/directories.yml` |
| 5 | Templates | 5 template files |
| 6 | Configuration deployment | `tasks/configure.yml` |
| 7 | Docker deployment | `tasks/docker.yml` |
| 8 | Verification | `tasks/verify.yml` |
| 9 | Playbook | `router-hosts-playbook.yml` |
| 10 | Validation and PR | lint, docs, PR |

Total: 10 tasks, ~12 commits, ~20 files created/modified
