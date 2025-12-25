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
- `neovim` - Modern vim editor (via homebrew feature)
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

### Pre-Setup: Store Your Anthropic API Key (Optional)

For Claude Code to work immediately, store your API key in Vault **before** starting the container:

```bash
# On your host machine (not in the container)
export VAULT_ADDR=https://vault.fzymgc.house
vault login -method=oidc

# Store your Anthropic API key (replace <your-username> with your Vault entity name)
vault kv put secret/users/<your-username>/anthropic api_key=sk-ant-...
```

If you skip this step, the `login-setup.sh` script inside the container will prompt you to store the key interactively.

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
- Authenticate to Vault (OIDC)
- Store or retrieve your Anthropic API key
- Authenticate to GitHub CLI
- Authenticate to Terraform Cloud

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

### Claude Code API Key Setup

The Anthropic API key is stored in Vault and configured automatically when you run `login-setup.sh`.

**Recommended:** Run the interactive setup:
```bash
bash .devcontainer/login-setup.sh
```

**Manual setup** (if needed):
```bash
# Authenticate to Vault
vault login -method=oidc

# Store your Anthropic API key (your entity name is usually your username)
vault kv put secret/users/<your-entity-name>/anthropic api_key=sk-ant-...

# Configure the API key for Claude Code
bash .devcontainer/setup-claude-secrets.sh
```

The setup script exit codes:

| Exit Code | Meaning |
|-----------|---------|
| 0 | Success - API key configured |
| 2 | Vault auth skipped - not logged in |
| 3 | API key not found in Vault |
| 1 | Error (CLI missing, command failure) |

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

## Further Reading

- [VS Code Dev Containers Documentation](https://code.visualstudio.com/docs/devcontainers/containers)
- [Dev Container Specification](https://containers.dev/)
- Repository-specific guides in `docs/`
