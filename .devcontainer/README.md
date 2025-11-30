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

### Utilities
- `jq`, `yq` - JSON/YAML processing
- `direnv` - Environment variable management
- Git, SSH, and essential build tools
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
   - `~/.vault-token` - Vault authentication token

### Opening the Repository in a Container

1. Open this repository in VS Code
2. Press `F1` or `Cmd/Ctrl+Shift+P`
3. Select **"Dev Containers: Reopen in Container"**
4. Wait for the container to build and initialize (first time takes 5-10 minutes)

The container will automatically:
- Build the Docker image with all tools
- Mount your SSH keys, kubeconfig, and 1Password socket
- Run the `post-create.sh` script to set up Python venv
- Install all Python and Ansible dependencies

### Verifying the Setup

Once the container is running, open a terminal and check:

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
curl -s https://vault.fzymgc.house/v1/sys/health | jq

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

The following host directories are mounted into the container:

| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `~/.ssh` | `/home/vscode/.ssh` | SSH keys (read-only) |
| `~/.kube` | `/home/vscode/.kube` | Kubernetes config |
| `~/.vault-token` | `/home/vscode/.vault-token` | Vault authentication |
| 1Password socket | `/home/vscode/.1password/agent.sock` | SSH agent for Git/SSH operations |

**Note:** Changes to these files inside the container affect your host system.

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
