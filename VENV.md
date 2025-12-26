# Python Virtual Environment Setup

This repository uses a Python virtual environment to manage Ansible and its dependencies in an isolated, repeatable manner.

## Quick Start

### Initial Setup

```bash
# Run the setup script (one-time setup)
./setup-venv.sh

# Activate the virtual environment
source .venv/bin/activate
```

### Daily Usage

```bash
# Activate virtual environment
source .venv/bin/activate

# Run Ansible commands
ansible-playbook -i ansible/inventory/hosts.yml ansible/k3s-playbook.yml

# When done, deactivate
deactivate
```

## What Gets Installed

### Python Packages (`requirements.txt`)
- **ansible** (>=11.0.0) - Full Ansible with bundled community collections
- **kubernetes** - Python Kubernetes client for k8s module
- **hvac** - HashiCorp Vault Python client
- **jmespath, netaddr, dnspython** - Ansible filter dependencies
- **ansible-lint, yamllint** - Code quality tools

### Ansible Collections (`ansible/requirements.yml`)
- **kubernetes.core** - Kubernetes management
- **community.general** - General utilities
- **community.hashi_vault** - Vault integration
- **ansible.posix** - POSIX system utilities
- **community.docker** - Docker management

## Manual Setup (Alternative)

If you prefer manual setup or `setup-venv.sh` doesn't work:

```bash
# Create virtual environment
python3 -m venv .venv

# Activate it
source .venv/bin/activate

# Upgrade pip
pip install --upgrade pip setuptools wheel

# Install Python packages
pip install -r requirements.txt

# Install Ansible collections
ansible-galaxy collection install -r ansible/requirements.yml

# Verify installation
ansible --version
```

## Updating Dependencies

### Update Python Packages

```bash
source .venv/bin/activate
pip install --upgrade -r requirements.txt
```

### Update Ansible Collections

```bash
source .venv/bin/activate
ansible-galaxy collection install -r ansible/requirements.yml --force
```

### Full Refresh

```bash
# Remove existing virtual environment
rm -rf .venv

# Run setup again
./setup-venv.sh
```

## Shell Integration

### Automatic Activation (Optional)

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# Auto-activate venv when entering this directory
if [[ -f .venv/bin/activate ]]; then
    source .venv/bin/activate
fi
```

### Using direnv (Recommended)

Create `.envrc` in repository root:

```bash
source .venv/bin/activate
```

Then run:

```bash
direnv allow
```

## Verifying Installation

```bash
source .venv/bin/activate

# Check Ansible version
ansible --version

# Check installed collections
ansible-galaxy collection list

# Check Python packages
pip list | grep -E "ansible|kubernetes|hvac"

# Run a test playbook
ansible-playbook -i ansible/inventory/hosts.yml ansible/k3s-playbook.yml --check
```

## Troubleshooting

### Python Version Issues

The repository requires Python 3.13+. Check `.python-version` for the exact version.

```bash
# Check your Python version
python3 --version

# If you need to install Python 3.13
# macOS with Homebrew:
brew install python@3.13

# Linux (Ubuntu/Debian):
sudo apt install python3.13 python3.13-venv

# Set as default (optional)
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 1
```

### Virtual Environment Not Activating

```bash
# Make sure you're in the repository root
cd /path/to/selfhosted-cluster

# Try absolute path
source "$(pwd)/.venv/bin/activate"
```

### Collection Installation Fails

```bash
# Clear Ansible cache
rm -rf ~/.ansible/collections

# Reinstall with verbose output
ansible-galaxy collection install -r ansible/requirements.yml -vvv
```

### Permission Errors

```bash
# Ensure script is executable
chmod +x setup-venv.sh

# Run with explicit shell
bash setup-venv.sh
```

## CI/CD Integration

For automated pipelines, use the setup script:

```yaml
# Example GitHub Actions
- name: Setup Ansible
  run: |
    ./setup-venv.sh
    source .venv/bin/activate
    ansible --version
```

## Why Virtual Environment?

1. **Isolation** - Dependencies don't conflict with system packages
2. **Repeatability** - Same versions across all environments
3. **Version Control** - Pin exact versions in requirements.txt
4. **Clean System** - No need for system-wide Ansible installation
5. **Multiple Projects** - Different Ansible versions per project

## Best Practices

1. **Always activate before running Ansible commands**
2. **Update dependencies periodically** (monthly recommended)
3. **Test updates in non-production first**
4. **Commit requirements.txt changes** to share with team
5. **Document custom packages** in requirements.txt with comments

## Related Files

- `requirements.txt` - Python package dependencies
- `ansible/requirements.yml` - Ansible Galaxy collections
- `.python-version` - Required Python version (3.13.7)
- `setup-venv.sh` - Automated setup script
- `.gitignore` - Excludes .venv/ from version control
