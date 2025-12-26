# .devcontainer/CLAUDE.md

AI assistant guidance for working with devcontainer configuration.

## Directory Structure

| File/Directory | Purpose |
|----------------|---------|
| `devcontainer.json` | Main config for local development (has host bind mounts) |
| `ci/devcontainer.json` | CI-specific config (no host bind mounts) |
| `Dockerfile` | Base image, shell aliases, default shell (zsh) |
| `post-create.sh` | Post-creation setup (venv, git config, brew tools, safeguards) |
| `login-setup.sh` | Interactive auth setup (Claude, Vault, GitHub, Terraform) |
| `setup-claude-secrets.sh` | Verifies MCP server API keys from Vault |
| `README.md` | Comprehensive user documentation |

**Related:**
- `scripts/create-vault-token.sh` - Creates Vault token on host for container auth (run on HOST, not in container)
- `.claude/settings.json` - Declarative plugin config (`extraKnownMarketplaces`, `enabledPlugins`)

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

### Shell Configuration

**Default shell:** zsh (set in Dockerfile `CMD` and VS Code terminal settings)

**CRITICAL: Dual-shell sync requirement:**
- Aliases and shell functions **MUST** be added to both `.zshrc` AND `.bashrc`
- Scripts may invoke `/bin/bash` explicitly, bypassing zsh
- Use a loop pattern in Dockerfile:
```dockerfile
RUN for rc in /home/vscode/.zshrc /home/vscode/.bashrc; do \
        echo 'alias foo=bar' >> "$rc"; \
    done
```

| Config Location | What Goes There |
|-----------------|-----------------|
| `Dockerfile` | Static aliases (cat→bat, top→btm, etc.) |
| `post-create.sh` | Dynamic config (git safeguards, tool checks) |
| `devcontainer.json` | VS Code terminal settings |

### Git Configuration

Git is configured **programmatically** in `post-create.sh`, NOT via mounted `~/.gitconfig`.

**Why:** Host gitconfig contains paths (credential helpers, GPG programs) that don't exist in container.

| Setting | Source |
|---------|--------|
| User name/email | `GIT_AUTHOR_NAME`/`GIT_AUTHOR_EMAIL` env vars (via `remoteEnv`) |
| Pager | delta (installed in Dockerfile) |
| Credential helper | GitHub CLI (`gh auth setup-git`) |
| GPG signing | Disabled locally (`git config --local commit.gpgsign false`) |

### Homebrew Tools

Modern CLI tools are installed via Homebrew feature + `post-create.sh`:

1. Feature `ghcr.io/meaningful-ooo/devcontainer-features/homebrew:2` provides brew
2. `post-create.sh` installs: `bat`, `bottom`, `git-delta`, `gping`, `procs`, `broot`, `tokei`, `xh`
3. Aliases defined in Dockerfile map traditional commands to modern equivalents

**Adding a new brew tool:**
1. Add to `BREW_TOOLS` list in `post-create.sh`
2. Add alias to Dockerfile (if replacing a standard command)
3. Add to README.md tool list
4. Update "Available tools" echo section in `post-create.sh`

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
- Configures git (identity from env vars, delta pager, gh credential helper, aliases)
- Initializes git-lfs
- Installs Homebrew CLI tools (bat, bottom, gping, procs, broot, tokei, xh)
- Sets up git safeguards in both `.zshrc` and `.bashrc`
- Loads MCP server API keys from Vault (via direnv)

**Pattern:** Non-blocking checks with warnings, not errors.

**Shell config updates:** When adding shell functions or aliases in `post-create.sh`, use a loop:
```bash
for rcfile in /home/vscode/.zshrc /home/vscode/.bashrc; do
    echo 'your_config' >> "$rcfile"
done
```

## CI Workflow

The `devcontainer-ci.yml` workflow:
1. Uses `devcontainers/ci@v0.3` action
2. Points to `ci/devcontainer.json` via `configFile` parameter
3. Runs validation commands to verify tools are installed

**Triggers:** Changes to `.devcontainer/**`, `setup-venv.sh`, `pyproject.toml`, `uv.lock`, `ansible/requirements.yml`

## Sync Requirements

When modifying devcontainer config:

| Change | Update CI Config? | Update README? | Update Workflow? |
|--------|-------------------|----------------|------------------|
| Add feature | Yes | Yes (if user-facing) | Maybe (if tool should be validated) |
| Add bind mount | No (CI can't use) | Yes | No |
| Add Docker volume | Yes | Yes | No |
| Change Dockerfile | Automatic (shared) | Maybe | No |
| Add shell alias | N/A (Dockerfile) | Yes | No |
| Add brew tool | N/A (post-create.sh) | Yes | No |
| Add validation check | No | No | Yes |
| Change shell config | Add to BOTH .zshrc AND .bashrc | Yes | No |

**CRITICAL:** Shell aliases and functions **MUST** go to both `.zshrc` and `.bashrc`.

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
