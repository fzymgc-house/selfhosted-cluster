# .devcontainer/CLAUDE.md

AI assistant guidance for working with devcontainer configuration.

## Directory Structure

| File/Directory | Purpose |
|----------------|---------|
| `devcontainer.json` | Main config for local development (has host bind mounts) |
| `ci/devcontainer.json` | CI-specific config (no host bind mounts) |
| `Dockerfile` | Base image with system packages |
| `post-create.sh` | Post-creation setup (venv, auth checks, git config) |
| `login-setup.sh` | Interactive auth setup (Claude, Vault, GitHub, Terraform) |
| `setup-claude-secrets.sh` | Verifies MCP server API keys from Vault |
| `README.md` | Comprehensive user documentation |

**Related:** `scripts/create-vault-token.sh` - Creates Vault token on host for container auth (run on HOST, not in container)

## Key Concepts

### Two Config Pattern

| Config | Location | Use Case |
|--------|----------|----------|
| Main | `devcontainer.json` | Local development with host mounts |
| CI | `ci/devcontainer.json` | GitHub Actions (no host paths) |

**Why two configs:** Host bind mounts (like `~/.ssh`) fail in CI because those paths don't exist on GitHub runners. CI config uses Docker volumes only.

### Mount Types

| Type | Syntax | Behavior |
|------|--------|----------|
| Bind mount | `source=${localEnv:HOME}/.ssh,...,type=bind` | Maps host path (must exist) |
| Docker volume | `source=volume-name,...,type=volume` | Container storage (auto-created) |

**Rule:** Use bind mounts for host secrets, Docker volumes for caches/state.

### Feature-Based Tools

Most tools are installed via devcontainer features (not Dockerfile):

```json
"features": {
    "ghcr.io/devcontainers/features/terraform:1": {},
    "ghcr.io/anthropics/devcontainer-features/claude-code:1": {}
}
```

**Adding tools:** Prefer features over Dockerfile when available. Features are maintained upstream.

## Common Tasks

### Adding a New Tool

1. Check [containers.dev/features](https://containers.dev/features) for existing feature
2. If feature exists: Add to `features` in both configs
3. If no feature: Add to `Dockerfile` with `apt-get install`
4. Update `devcontainer-ci.yml` validation if tool should be checked

### Modifying Mounts

1. Update `devcontainer.json` with the mount
2. If mount is host-specific (bind mount): **DO NOT** add to `ci/devcontainer.json`
3. If mount is Docker volume: Add to both configs
4. Test locally, then verify CI passes

### Updating Post-Create Script

The `post-create.sh` runs after container creation:
- Fixes Docker volume permissions
- Checks auth status (Vault, GitHub, Terraform, Claude)
- Runs `setup-venv.sh` for Python environment
- Configures git defaults
- Loads MCP server API keys from Vault (via direnv)

**Pattern:** Non-blocking checks with warnings, not errors.

## CI Workflow

The `devcontainer-ci.yml` workflow:
1. Uses `devcontainers/ci@v0.3` action
2. Points to `ci/devcontainer.json` via `configFile` parameter
3. Runs validation commands to verify tools are installed

**Triggers:** Changes to `.devcontainer/**`, `setup-venv.sh`, `requirements.txt`, `ansible/requirements-ansible.yml`

## Sync Requirements

When modifying devcontainer config:

| Change | Update CI Config? | Update Workflow? |
|--------|-------------------|------------------|
| Add feature | Yes | Maybe (if tool should be validated) |
| Add bind mount | No (CI can't use) | No |
| Add Docker volume | Yes | No |
| Change Dockerfile | Automatic (shared) | No |
| Add validation check | No | Yes |

## Testing Changes

```bash
# Local build
devcontainer build --workspace-folder .

# CI build (mimics GitHub Actions)
devcontainer build --workspace-folder . --config .devcontainer/ci/devcontainer.json

# Full test with validation
devcontainer up --workspace-folder . --config .devcontainer/ci/devcontainer.json
devcontainer exec --workspace-folder . bash -c "python --version && terraform version"
```
