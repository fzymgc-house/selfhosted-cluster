# Development Container Configuration

This directory contains the devcontainer configuration for isolated development of the self-hosted cluster infrastructure.

## What's Included

The devcontainer provides a complete, reproducible development environment with:

### Core Tools
- **Python 3.13** with virtual environment support
- **Terraform** for infrastructure as code
- **Ansible** for cluster automation
- **kubectl** for Kubernetes management
- **Helm** for Kubernetes package management
- **GitHub CLI (gh)** for PR and repository management
- **1Password SSH Agent** for SSH key management (via socket proxy)
- **k3sup** for k3s cluster management

### AI Development
- **Claude Code** - Anthropic's CLI for AI-assisted development
- **MCP Servers** - filesystem, kubernetes, context7, firecrawl, exa, notion, serena
- **ripgrep** - Fast code search (required by Serena MCP)
- **ast-grep** - Structural code search for semantic analysis

### Utilities
- `jq`, `yq` - JSON/YAML processing (via jq-likes feature)
- `direnv` - Automatic environment variable loading (via feature)
- `go-task` - Task runner (via feature)
- `neovim` - Modern vim editor (via devcontainer feature)
- Git, SSH, SSHD, and essential build tools
- Docker-in-Docker support
- 1Password SSH Agent integration (via socket proxy)

### Python Packages
All packages from `requirements.txt` are automatically installed:
- Ansible (core and full)
- Kubernetes Python client
- HashiCorp Vault client (hvac)
- Network utilities (netaddr, dnspython)
- Linting tools (ansible-lint, yamllint)

### Ansible Collections
All collections from `ansible/requirements-ansible.yml`:
- kubernetes.core
- community.general
- community.hashi_vault
- ansible.posix
- community.docker

## Getting Started

### Prerequisites

1. **VS Code** with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
2. **Docker Desktop** or Docker Engine running
3. **socat** (for 1Password socket proxy): `brew install socat`
4. **1Password** with SSH agent enabled (for SSH key management)
5. **Host prerequisites** (automatically mounted):
   - `~/.ssh` - SSH keys for Git and cluster access
   - `~/.kube/config` - Kubernetes cluster configuration
   - `~/.1password/agent.sock` - 1Password SSH agent socket

### Pre-Setup: Store Credentials in Vault (Optional)

For faster setup, pre-store your credentials in Vault **before** starting the container:

```bash
# On your host machine (not in the container)
export VAULT_ADDR=https://vault.fzymgc.house
vault login -method=oidc

# Store Terraform Cloud token (replace <your-username> with your Vault entity name)
vault kv put secret/users/<your-username>/terraform-cloud token=...

# Store MCP server API keys (optional - for enhanced Claude Code features)
vault kv put secret/users/<your-username>/firecrawl api_key=fc-...
vault kv put secret/users/<your-username>/exa api_key=...
vault kv put secret/users/<your-username>/notion api_key=secret_...
```

If you skip this, `login-setup.sh` will prompt you interactively. Claude Code itself uses OAuth login via `claude doctor`.

### Opening the Repository in a Container

**Recommended: Clone in Container Volume**

This approach clones the repository into a Docker volume, avoiding host filesystem issues:

1. Open VS Code (without opening a folder)
2. Press `F1` or `Cmd/Ctrl+Shift+P`
3. Select **"Dev Containers: Clone Repository in Container Volume..."**
4. Enter the repository URL: `https://github.com/fzymgc-house/selfhosted-cluster`
5. Wait for the container to build and initialize (first time takes 5-10 minutes)

**Alternative: Open Existing Clone**

If you have the repository cloned locally:

1. Open the repository folder in VS Code
2. Press `F1` or `Cmd/Ctrl+Shift+P`
3. Select **"Dev Containers: Reopen in Container"**

The container will automatically:
- Build the Docker image with all tools
- Clone (or mount) the repository into `/workspaces/selfhosted-cluster`
- Mount your SSH keys, kubeconfig, and 1Password socket
- Run the `post-create.sh` script to set up Python venv
- Install all Python and Ansible dependencies

### First-Time Setup

Once the container is running, open a terminal and run the interactive login setup:

```bash
# Complete authentication for Vault, GitHub, Terraform, and Claude Code
bash .devcontainer/login-setup.sh
```

This script will:
- Authenticate to Vault (token-based, OIDC not supported in container)
- Store/retrieve MCP server API keys (optional)
- Store/retrieve Terraform Cloud token and create credentials file
- Authenticate to GitHub CLI
- Run `claude doctor` for Claude Code OAuth login

### Verifying the Setup

After running login-setup.sh, verify your environment:

```bash
# Check Python environment
python --version          # Should be 3.13.x
source .venv/bin/activate
ansible --version         # Should show Ansible installation

# Check Terraform
terraform version

# Check Kubernetes access
kubectl --context fzymgc-house get nodes

# Check Vault connectivity
vault token lookup

# Check SSH agent (1Password keys)
ssh-add -L
```

## Working with the Container

### Python Virtual Environment

The virtual environment is automatically created at `.venv/`:

```bash
# Activate (if not already active)
source .venv/bin/activate

# Deactivate
deactivate

# Reinstall dependencies
pip install -r requirements.txt
ansible-galaxy collection install -r ansible/requirements-ansible.yml
```

### Terraform Operations

```bash
cd tf/authentik
terraform init
terraform plan
terraform apply
```

### Ansible Operations

```bash
# Activate venv first
source .venv/bin/activate

# Run playbooks
ansible-playbook -i ansible/inventory/hosts.yml ansible/k3s-playbook.yml --check

# Test connectivity
ansible -i ansible/inventory/hosts.yml all -m ping
```

### Kubernetes Operations

```bash
# Use the alias (k = kubectl with default context fzymgc-house)
k get nodes
k get pods -A

# Or full command (context is already set as default)
kubectl get nodes
```

## Helpful Aliases

The container includes these pre-configured aliases:

- `k` → `kubectl` (default context: fzymgc-house)
- `tf` → `terraform`
- `ll` → `ls -alh`

## Mounted Volumes

### Host Bind Mounts
| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `~/.ssh` | `/home/vscode/.ssh` | SSH keys (read-only) |
| `~/.kube` | `/home/vscode/.kube` | Kubernetes config |
| `~/.1password` | `/home/vscode/.1password` | 1Password SSH agent socket |

### Docker Volumes (Persist Across Rebuilds)
| Volume Name | Container Path | Purpose |
|-------------|----------------|---------|
| `selfhosted-cluster-claude-config` | `/home/vscode/.claude` | Claude Code settings |
| `selfhosted-cluster-venv` | `/workspaces/<folder>/.venv` | Python virtual environment |
| `selfhosted-cluster-cache` | `/home/vscode/.cache` | XDG cache (pip, uv, etc.) |
| `selfhosted-cluster-tmp` | `/tmp` | Temporary files |

**Note:** The venv path uses `${localWorkspaceFolderBasename}`, so it adapts to the workspace folder name (e.g., `selfhosted-cluster` for volume clone, or `devcontainer-claude-code` for worktree).

**Notes:**
- Host bind mounts: Changes inside the container affect your host system
- Vault tokens are **not** mounted - you must authenticate inside the container with `vault login`
- Claude Code config uses a Docker volume for persistence across rebuilds

## Environment Variables

Pre-configured environment variables:

- `KUBECONFIG=/home/vscode/.kube/config`
- `VAULT_ADDR=https://vault.fzymgc.house`
- `SSH_AUTH_SOCK` - Forwarded from host

Additional environment variables can be set in `.envrc` (automatically loaded with direnv).

## VS Code Extensions

The following extensions are automatically installed:

- HashiCorp Terraform
- Red Hat Ansible
- Python + Pylance
- Kubernetes Tools
- YAML Support
- Prettier
- GitHub Copilot (if available)

## Customization

### Adding More Tools

Edit `.devcontainer/Dockerfile` to add system packages:

```dockerfile
RUN apt-get update && apt-get install -y \
    your-package-here \
    && rm -rf /var/lib/apt/lists/*
```

### Adding Python Packages

Add to `requirements.txt` in the root, then rebuild:

```bash
# In VS Code command palette
Dev Containers: Rebuild Container
```

### Adding VS Code Extensions

Edit `.devcontainer/devcontainer.json` under `customizations.vscode.extensions`.

## Troubleshooting

### Container Won't Start

```bash
# Check Docker is running
docker ps

# View container logs
docker logs <container-id>

# Rebuild from scratch
Dev Containers: Rebuild Container Without Cache
```

### Permission Issues

```bash
# Fix ownership of mounted volumes
sudo chown -R $(id -u):$(id -g) ~/.kube ~/.ssh
```

### 1Password SSH Agent

**Working Solution:** The 1Password SSH agent is integrated via a `socat` proxy that works around Docker Desktop's limitation with paths containing spaces.

**What Works:**
- ✅ SSH keys from 1Password available in the container
- ✅ Git/GitHub authentication using 1Password SSH keys
- ✅ Any SSH operations using keys stored in 1Password

**Setup:**
The `dev.sh` script automatically creates a socket proxy when starting the container:
```bash
# Start container (proxy auto-created)
./dev.sh up

# Test SSH keys
./dev.sh exec "ssh-add -L"

# Use Git with 1Password keys
./dev.sh exec "git fetch"
```

**Note:** Only the 1Password SSH agent socket is available in the container. This provides SSH key access for Git and SSH operations, which is all that's needed for development workflows.

### Claude Code Authentication

Claude Code uses interactive OAuth login. Run inside the devcontainer:
```bash
claude doctor
```
This checks your environment and prompts for login if needed. Your session is stored in `~/.claude.json`.

**Recommended:** Run the interactive setup which handles all authentication:
```bash
bash .devcontainer/login-setup.sh
```

### Vault-Stored Credentials

Credentials for MCP servers and Terraform Cloud are stored in Vault and managed via `login-setup.sh`.

**Important:** Vault OIDC login requires a localhost:8250 callback, which doesn't work in devcontainers. Use the helper script to create a token on your **host machine**:

```bash
# On your HOST (not in container), from repo root:
./scripts/create-vault-token.sh
# Token is copied to clipboard (or displayed if clipboard unavailable)
```

Then in the devcontainer:
```bash
# Paste the token when prompted by login-setup.sh
bash .devcontainer/login-setup.sh

# Or manually:
vault login token=<paste-token-here>
vault kv put secret/users/<your-entity-name>/terraform-cloud token=...
vault kv put secret/users/<your-entity-name>/firecrawl api_key=fc-...
vault kv put secret/users/<your-entity-name>/exa api_key=...
vault kv put secret/users/<your-entity-name>/notion api_key=secret_...
direnv allow
```

**How it works:**
- Terraform Cloud token is stored in Vault and used to create `~/.terraform.d/credentials.tfrc.json`
- MCP server API keys are loaded via direnv when you enter the workspace directory

| Credential | Vault Path | Purpose |
|------------|------------|---------|
| Terraform Cloud | `secret/users/<name>/terraform-cloud` | Infrastructure remote state |
| Firecrawl | `secret/users/<name>/firecrawl` | Web scraping/search MCP |
| Exa | `secret/users/<name>/exa` | Deep research MCP |
| Notion | `secret/users/<name>/notion` | Notion workspace MCP |

### kubectl Context Not Found

```bash
# List available contexts
kubectl config get-contexts

# If fzymgc-house doesn't exist, you'll need to set it up:
# 1. Copy kubeconfig from your k3s cluster
# 2. Add to ~/.kube/config on host
# 3. Rebuild container
```

## Performance Tips

1. **Use Docker Desktop's resource settings** to allocate sufficient CPU/memory
2. **Exclude .venv from file watching** to improve performance
3. **Use volume mounts** for source code (already configured)

## Security Considerations

- SSH keys are mounted read-only
- Secrets are managed via HashiCorp Vault, never committed to Git
- The container has access to your cluster - use carefully
- Docker-in-Docker is enabled - be cautious with untrusted images
- 1Password SSH agent provides secure SSH key access without exposing private keys

## CI/CD Validation

The devcontainer is validated on every PR via GitHub Actions (`.github/workflows/devcontainer-ci.yml`).

### CI-Specific Configuration

CI uses a separate config at `.devcontainer/ci/devcontainer.json` because:

| Mount Type | Local Development | CI/GitHub Actions |
|------------|-------------------|-------------------|
| Host bind mounts (`~/.ssh`, `~/.kube`) | ✅ Works (host paths exist) | ❌ Fails (paths don't exist on runners) |
| Docker volumes | ✅ Works | ✅ Works (auto-created) |

The CI config removes host-specific bind mounts while keeping Docker volumes for caches.

### What CI Validates

The workflow builds the devcontainer and validates:
- Core tools: Python, uv, Terraform, Ansible, kubectl, Helm, GitHub CLI
- Development tools: ripgrep, ast-grep, jq, yq
- Python virtual environment setup (when present)

### Running CI Locally

Test the CI build locally with the devcontainers CLI:

```bash
# Install CLI
npm install -g @devcontainers/cli

# Build using CI config
devcontainer build --workspace-folder . --config .devcontainer/ci/devcontainer.json

# Run with validation
devcontainer up --workspace-folder . --config .devcontainer/ci/devcontainer.json
devcontainer exec --workspace-folder . python --version
```

## Architecture Notes

### Host Bind Mounts vs Docker Volumes

| Type | Behavior | Use Case |
|------|----------|----------|
| **Bind mount** (`type=bind`) | Maps host path into container | Host secrets (SSH keys, kubeconfig) |
| **Docker volume** (`type=volume`) | Container-only storage, persists across rebuilds | Caches, venv, Claude config |

**Key insight:** Bind mounts require the host path to exist. This is why CI needs a separate config without host-specific mounts.

### Volume Naming

Docker volumes use a `selfhosted-cluster-` prefix for easy identification:
- `selfhosted-cluster-claude-config` - Claude Code settings
- `selfhosted-cluster-venv` - Python virtual environment
- `selfhosted-cluster-cache` - XDG cache (pip, uv, etc.)
- `selfhosted-cluster-tmp` - Temporary files

## Further Reading

- [VS Code Dev Containers Documentation](https://code.visualstudio.com/docs/devcontainers/containers)
- [Dev Container Specification](https://containers.dev/)
- [devcontainers/ci GitHub Action](https://github.com/devcontainers/ci)
- Repository-specific guides in `docs/`
