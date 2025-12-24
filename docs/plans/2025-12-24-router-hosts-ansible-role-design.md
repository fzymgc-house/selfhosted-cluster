# Router-Hosts Ansible Role Design

**Status:** Approved
**Date:** 2025-12-24
**Author:** Claude (with Sean)

## Overview

Deploy router-hosts server on Firewalla using Docker Compose with Vault Agent for automated mTLS certificate management.

## Requirements

- Deploy router-hosts `v0.6.0` via Docker Compose
- Use Vault Agent for automatic certificate provisioning and renewal
- Fetch AppRole credentials from Vault at deploy time
- Store data on external storage (`/extdata/router-hosts`)
- Integrate with Firewalla's `docker-compose@` systemd service
- Auto-start on boot via `post_main.d` script

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Firewalla (router)                                              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ docker-compose@router-hosts                              │   │
│  │                                                          │   │
│  │  ┌──────────────┐      ┌─────────────────────────────┐  │   │
│  │  │ vault-agent  │─────▶│ router-hosts-server         │  │   │
│  │  │              │certs │                             │  │   │
│  │  │ Fetches certs│      │ gRPC :50051                 │  │   │
│  │  │ from Vault   │      │ Manages /data/hosts         │  │   │
│  │  └──────────────┘      └─────────────────────────────┘  │   │
│  │         │                         │                      │   │
│  │         ▼                         ▼                      │   │
│  │  /extdata/router-hosts/    /extdata/router-hosts/        │   │
│  │  vault-approle/            data/                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  vault.fzymgc.house ◀─── PKI: fzymgc-house/v1/ica1/v1          │
└─────────────────────────────────────────────────────────────────┘
```

## Directory Layout

### Firewalla-Managed Locations

```
/home/pi/.firewalla/run/docker/router-hosts/
└── docker-compose.yml

/home/pi/.firewalla/config/post_main.d/
└── z0100-start-router-hosts.sh
```

### External Storage

```
/extdata/router-hosts/
├── config/
│   └── server.toml
├── data/                       # DuckDB database + generated hosts file
├── vault-approle/
│   ├── role_id
│   └── secret_id
└── scripts/
    └── on-hosts-update.sh
```

## Role Structure

```
ansible/roles/router-hosts/
├── defaults/main.yml
├── tasks/
│   ├── main.yml
│   ├── preflight.yml
│   ├── vault-credentials.yml
│   ├── directories.yml
│   ├── configure.yml
│   ├── docker.yml
│   └── verify.yml
├── templates/
│   ├── docker-compose.yml.j2
│   ├── server.toml.j2
│   ├── vault-agent-config.hcl.j2
│   ├── on-hosts-update.sh.j2
│   └── z0100-start-router-hosts.sh.j2
├── handlers/main.yml
└── meta/main.yml
```

## Configuration

### Default Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `router_hosts_base_dir` | `/extdata/router-hosts` | Base directory for config/data |
| `router_hosts_image` | `ghcr.io/fzymgc-house/router-hosts` | Container image |
| `router_hosts_version` | `v0.6.0` | Pinned version |
| `router_hosts_vault_image` | `hashicorp/vault:1.18` | Vault Agent image |
| `router_hosts_vault_addr` | `https://vault.fzymgc.house` | Vault server |
| `router_hosts_vault_pki_path` | `fzymgc-house/v1/ica1/v1` | PKI mount path |
| `router_hosts_vault_approle_name` | `router-hosts-agent` | AppRole name |
| `router_hosts_grpc_port` | `50051` | gRPC listen port |
| `router_hosts_user` | `pi` | Container user |

### Certificate Configuration

| Setting | Value |
|---------|-------|
| Common Name | `router-hosts` |
| DNS SANs | `localhost`, `router.fzymgc.house`, `router`, `router.local` |
| IP SANs | `127.0.0.1`, `192.168.20.1`, `fddb:f665:73f7:1::1`, `fe80::226d:31ff:fe31:715` |
| TTL | 30 days (720h) |

## Task Execution Order

1. **Preflight** - Verify Docker running, check Vault connectivity
2. **Vault Credentials** - Fetch `role_id`, generate `secret_id` (delegated to localhost)
3. **Directories** - Create directory structure, set permissions
4. **Configure** - Deploy all templates
5. **Docker** - Pull images, start `docker-compose@router-hosts` service
6. **Verify** - Wait for Vault Agent health, verify gRPC port

## Key Files

### docker-compose.yml

Two services:
- `vault-agent` - Fetches and renews certificates from Vault PKI
- `router-hosts` - gRPC server with mTLS

Volumes mount from `/extdata/router-hosts/`.

### vault-agent-config.hcl

- AppRole authentication from `/extdata/router-hosts/vault-approle/`
- Certificate templates write to shared volume
- `share_dependencies = true` ensures matching cert/key pairs
- 5-minute renewal check interval

### on-hosts-update.sh

Hook script called after hosts file updates. Currently a no-op that logs:
```bash
#!/usr/bin/env bash
# TODO: Uncomment to restart Firewalla DNS
# sudo systemctl restart firerouter_dns
logger -t router-hosts "Hosts file updated"
```

### z0100-start-router-hosts.sh

Boot script in `post_main.d`:
```bash
#!/usr/bin/env bash
sudo systemctl enable --now docker-compose@router-hosts
```

## Playbook

**File:** `ansible/router-hosts-playbook.yml`

```yaml
---
- name: Deploy router-hosts to Firewalla
  hosts: router
  become: true
  roles:
    - router-hosts
```

**Prerequisites:**
- Vault token available (via `VAULT_TOKEN` or `vault login`)
- `community.hashi_vault` collection installed

**Usage:**
```bash
ansible-playbook -i inventory/hosts.yml router-hosts-playbook.yml
```

## Vault Infrastructure

Already configured in `tf/vault/`:
- `pki-router-hosts.tf` - PKI roles for server/client certificates
- `approle-router-hosts.tf` - AppRole `router-hosts-agent`
- `policy-router-hosts.tf` - Policy granting cert issuance

## Security Considerations

- AppRole credentials stored with mode `0600`
- Containers run as `pi` user (non-root)
- mTLS enforced for all gRPC connections
- Certificates auto-renew before expiration
- Vault Agent tokens are short-lived (1h TTL, 24h max)

## Future Work

- Enable `on-hosts-update.sh` hook to restart `firerouter_dns`
- Add monitoring/alerting for certificate renewal failures
- Consider client certificate provisioning for CLI access
