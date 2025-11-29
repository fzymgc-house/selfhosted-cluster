# Using Devcontainer from Terminal (Warp, iTerm2, etc.)

You can use the devcontainer configuration from any terminal without VS Code using the `devcontainer` CLI.

## Installation

### Option 1: Homebrew (Recommended for macOS)

```bash
brew install devcontainer
```

### Option 2: npm (Alternative)

```bash
npm install -g @devcontainers/cli
```

### Verify Installation

```bash
devcontainer --version
```

## Quick Start

### Build the Container

```bash
# From the repository root
devcontainer build --workspace-folder .
```

### Run the Container

```bash
# Start an interactive shell in the container
devcontainer up --workspace-folder .

# Execute commands in the running container
devcontainer exec --workspace-folder . bash

# Or combine both (build + run + exec)
devcontainer up --workspace-folder . && devcontainer exec --workspace-folder . bash
```

## Common Usage Patterns

### 1. Interactive Shell Session

```bash
# Build and start container, then open shell
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash -l

# Now you're inside the container!
# Your workspace is mounted at /workspace
cd /workspace
source .venv/bin/activate
ansible --version
```

### 2. Run Single Command

```bash
# Run a command without entering the container
devcontainer exec --workspace-folder . bash -c "cd /workspace && terraform version"

# Run Terraform plan
devcontainer exec --workspace-folder . bash -c "cd /workspace/tf/authentik && terraform plan"

# Run Ansible playbook
devcontainer exec --workspace-folder . bash -c "source /workspace/.venv/bin/activate && ansible-playbook -i ansible/inventory/hosts.yml ansible/k3s-playbook.yml --syntax-check"
```

### 3. Multiple Commands in One Session

```bash
devcontainer exec --workspace-folder . bash -c '
  cd /workspace
  source .venv/bin/activate
  echo "Checking Terraform..."
  terraform version
  echo "Checking Ansible..."
  ansible --version
  echo "Checking kubectl..."
  kubectl version --client
'
```

## Helper Script Usage

We've created a helper script `dev.sh` for easier access:

```bash
# Build the container
./dev.sh build

# Start interactive shell
./dev.sh shell

# Run a command
./dev.sh exec "terraform version"

# Run Ansible playbook
./dev.sh exec "source .venv/bin/activate && ansible-playbook -i ansible/inventory/hosts.yml playbook.yml --check"

# Stop the container
./dev.sh stop

# Rebuild from scratch
./dev.sh rebuild
```

## Using with Warp Terminal

### Option 1: Launch Script (Recommended)

Add this to your Warp workflows or create an alias:

```bash
# In your shell rc file (~/.zshrc, ~/.bashrc)
alias dev='./dev.sh shell'
alias devc='./dev.sh exec'
```

Then from Warp:
```bash
cd /path/to/selfhosted-cluster
dev          # Opens interactive shell in container
devc "ansible --version"  # Runs single command
```

### Option 2: Direct devcontainer Commands

```bash
# Create Warp workflow
# Name: "Dev Container Shell"
# Command:
cd /Volumes/Code/github.com/fzymgc-house/selfhosted-cluster && \
devcontainer up --workspace-folder . && \
devcontainer exec --workspace-folder . bash -l
```

## Using with iTerm2

### Create a Profile

1. Open iTerm2 → Preferences → Profiles
2. Create new profile: "Cluster Dev Container"
3. Set "Send text at start":
   ```bash
   cd /Volumes/Code/github.com/fzymgc-house/selfhosted-cluster && ./dev.sh shell
   ```
4. Save profile

Now just select this profile to jump into the dev container!

## Using with tmux

```bash
# Create a new tmux session in the container
devcontainer exec --workspace-folder . tmux new -s cluster

# Attach to existing session
devcontainer exec --workspace-folder . tmux attach -t cluster
```

## Persistence

The container maintains state between sessions:

- **Workspace files** are mounted from your host (live sync)
- **Python venv** is created in workspace (persists)
- **Container itself** persists until you explicitly remove it

To stop but keep the container:
```bash
docker stop $(docker ps -q --filter ancestor=vsc-selfhosted-cluster)
```

To remove and start fresh:
```bash
devcontainer down --workspace-folder .
# or
./dev.sh clean
```

## Advanced: Custom Entrypoint

If you want to automatically activate Python venv and set up environment:

```bash
devcontainer exec --workspace-folder . bash -c '
  cat << "SCRIPT" > /tmp/entrypoint.sh
#!/bin/bash
cd /workspace
source .venv/bin/activate 2>/dev/null || true
export PS1="[devcontainer] \w $ "
bash --login
SCRIPT
  chmod +x /tmp/entrypoint.sh
  /tmp/entrypoint.sh
'
```

## Environment Variables

Pass environment variables to the container:

```bash
devcontainer exec --workspace-folder . \
  --env VAULT_TOKEN=your-token \
  bash -c "vault kv list secret/"
```

## Troubleshooting

### Container Not Starting

```bash
# Check container logs
docker logs $(docker ps -aq --filter ancestor=vsc-selfhosted-cluster) --tail 100

# Rebuild from scratch
devcontainer down --workspace-folder .
devcontainer build --workspace-folder . --no-cache
```

### Command Not Found

```bash
# Ensure devcontainer CLI is installed
npm list -g @devcontainers/cli

# Reinstall if needed
npm uninstall -g @devcontainers/cli
npm install -g @devcontainers/cli
```

### Slow Build

```bash
# Use BuildKit for faster builds
export DOCKER_BUILDKIT=1
devcontainer build --workspace-folder .
```

## Integration with Shell Aliases

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
# Quick devcontainer access
alias dcbuild='cd /path/to/repo && devcontainer build --workspace-folder .'
alias dcup='cd /path/to/repo && devcontainer up --workspace-folder .'
alias dcexec='cd /path/to/repo && devcontainer exec --workspace-folder .'
alias dcshell='cd /path/to/repo && devcontainer exec --workspace-folder . bash -l'
alias dcdown='cd /path/to/repo && devcontainer down --workspace-folder .'

# Or use the helper script
alias dev='cd /path/to/repo && ./dev.sh shell'
```

## VS Code CLI Integration

You can still launch VS Code from terminal when needed:

```bash
# Open current container in VS Code
code .

# VS Code will detect the devcontainer and offer to reopen in container
```

## Benefits of CLI Usage

1. **Faster startup** - No VS Code overhead
2. **Better for automation** - Script-friendly
3. **tmux/screen compatible** - Full terminal multiplexing
4. **Resource efficient** - Use Warp/iTerm instead of Electron
5. **Flexibility** - Mix of container and native tools

## Next Steps

1. Install devcontainer CLI: `brew install devcontainer`
2. Build the container: `./dev.sh build`
3. Start working: `./dev.sh shell`
