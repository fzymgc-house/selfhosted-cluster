#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""
Script to migrate secrets from 1Password to HashiCorp Vault

This script:
1. Checks prerequisites (vault CLI, op CLI, ansible-vault)
2. Authenticates to Vault
3. Creates the infrastructure-developer policy
4. Extracts secrets from .envrc and 1Password
5. Creates secrets in Vault
6. Verifies secret access
"""

import os
import subprocess
import sys
from pathlib import Path


class Colors:
    """ANSI color codes for terminal output"""

    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    NC = "\033[0m"  # No Color


def log_info(message: str) -> None:
    """Log info message in green"""
    print(f"{Colors.GREEN}[INFO]{Colors.NC} {message}")


def log_warn(message: str) -> None:
    """Log warning message in yellow"""
    print(f"{Colors.YELLOW}[WARN]{Colors.NC} {message}")


def log_error(message: str) -> None:
    """Log error message in red"""
    print(f"{Colors.RED}[ERROR]{Colors.NC} {message}")


def log_step(message: str) -> None:
    """Log step message in blue"""
    print(f"{Colors.BLUE}[STEP]{Colors.NC} {message}")


def run_command(cmd: list[str], capture_output: bool = True, check: bool = False) -> tuple[int, str, str]:
    """
    Run a shell command and return exit code, stdout, stderr

    Args:
        cmd: Command and arguments as list
        capture_output: Whether to capture stdout/stderr
        check: Whether to raise exception on non-zero exit

    Returns:
        Tuple of (exit_code, stdout, stderr)
    """
    try:
        result = subprocess.run(cmd, capture_output=capture_output, text=True, check=check)
        return result.returncode, result.stdout, result.stderr
    except subprocess.CalledProcessError as e:
        return e.returncode, e.stdout, e.stderr
    except FileNotFoundError:
        return 127, "", f"Command not found: {cmd[0]}"


def check_prerequisites() -> bool:
    """Check that required tools are installed"""
    log_step("Checking prerequisites...")

    missing_tools = []

    # Check vault CLI
    exit_code, _, _ = run_command(["vault", "version"])
    if exit_code != 0:
        missing_tools.append("vault (HashiCorp Vault CLI)")

    # Check 1Password CLI (optional)
    exit_code, _, _ = run_command(["op", "--version"])
    if exit_code != 0:
        log_warn("1Password CLI not found (optional)")

    # Check ansible-vault
    exit_code, _, _ = run_command(["ansible-vault", "--version"])
    if exit_code != 0:
        missing_tools.append("ansible-vault (Ansible)")

    if missing_tools:
        log_error("Missing required tools:")
        for tool in missing_tools:
            print(f"  - {tool}")
        return False

    log_info("✓ All required tools found")
    return True


def check_vault_auth() -> bool:
    """Check Vault authentication and set VAULT_ADDR if needed"""
    log_step("Checking Vault authentication...")

    # Set VAULT_ADDR if not already set
    if "VAULT_ADDR" not in os.environ:
        os.environ["VAULT_ADDR"] = "https://vault.fzymgc.house"
        log_info(f"Set VAULT_ADDR={os.environ['VAULT_ADDR']}")

    # Check if already authenticated
    exit_code, _, _ = run_command(["vault", "token", "lookup"])
    if exit_code != 0:
        log_warn("Not authenticated to Vault")
        log_info("Running 'vault login'...")
        exit_code, _, _ = run_command(["vault", "login"], capture_output=False)
        if exit_code != 0:
            log_error("Vault login failed")
            return False
    else:
        log_info("✓ Vault authentication valid")

    return True


def create_vault_policy(repo_root: Path) -> bool:
    """Create the infrastructure-developer Vault policy"""
    log_step("Creating infrastructure-developer Vault policy...")

    policy_file = repo_root / "tf" / "vault" / "policy-infrastructure-developer.hcl"

    if not policy_file.exists():
        log_error(f"Policy file not found: {policy_file}")
        return False

    log_info(f"Creating policy from {policy_file}...")
    exit_code, _, stderr = run_command(["vault", "policy", "write", "infrastructure-developer", str(policy_file)])

    if exit_code == 0:
        log_info("✓ Created infrastructure-developer policy")
        return True
    else:
        log_warn(f"Failed to create policy (may already exist or insufficient permissions): {stderr}")
        return True  # Don't fail the entire script if policy already exists


def extract_secrets(repo_root: Path) -> dict[str, str | None]:
    """Extract secrets from .envrc and 1Password"""
    log_step("Extracting secrets from current sources...")

    secrets = {
        "TPI_ALPHA_BMC": None,
        "TPI_BETA_BMC": None,
        "CLOUDFLARE_TOKEN": None,
    }

    # Extract from .envrc (if it still has secrets - may already be migrated)
    envrc_file = repo_root / ".envrc"
    if envrc_file.exists():
        # Parse .envrc for environment variables
        try:
            with open(envrc_file) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("export TPI_ALPHA_BMC_ROOT_PW="):
                        value = line.split("=", 1)[1].strip('"').strip("'")
                        if value:
                            secrets["TPI_ALPHA_BMC"] = value
                            log_info("✓ Found TPI Alpha BMC password in .envrc")
                    elif line.startswith("export TPI_BETA_BMC_ROOT_PW="):
                        value = line.split("=", 1)[1].strip('"').strip("'")
                        if value:
                            secrets["TPI_BETA_BMC"] = value
                            log_info("✓ Found TPI Beta BMC password in .envrc")
        except Exception as e:
            log_warn(f"Failed to parse .envrc: {e}")
    else:
        log_warn(".envrc not found")

    # Check if we got values from .envrc
    if not secrets["TPI_ALPHA_BMC"]:
        log_warn("TPI Alpha BMC password not found in .envrc (may already be migrated)")
    if not secrets["TPI_BETA_BMC"]:
        log_warn("TPI Beta BMC password not found in .envrc (may already be migrated)")

    # Extract from 1Password (only if op command is available)
    exit_code, _, _ = run_command(["op", "--version"])
    if exit_code == 0:
        log_info("Extracting secrets from 1Password...")

        exit_code, stdout, _ = run_command(["op", "item", "get", "--vault", "fzymgc-house", "cloudflare-api-token", "--fields", "password", "--reveal"])

        if exit_code == 0 and stdout.strip():
            secrets["CLOUDFLARE_TOKEN"] = stdout.strip()
            log_info("✓ Found Cloudflare API token in 1Password")
        else:
            log_warn("Cloudflare API token not found in 1Password")
    else:
        log_warn("1Password CLI not available, skipping 1Password extraction")

    return secrets


def create_vault_secrets(secrets: dict[str, str | None]) -> list[str]:
    """
    Create secrets in Vault

    Returns:
        List of secret paths that were successfully created
    """
    log_step("Creating secrets in Vault...")

    created_secrets = []
    created = 0
    skipped = 0

    # Create BMC secrets
    if secrets["TPI_ALPHA_BMC"]:
        log_info("Creating secret/fzymgc-house/infrastructure/bmc/tpi-alpha...")
        exit_code, _, stderr = run_command(["vault", "kv", "put", "secret/fzymgc-house/infrastructure/bmc/tpi-alpha", f"password={secrets['TPI_ALPHA_BMC']}"])
        if exit_code == 0:
            created_secrets.append("secret/fzymgc-house/infrastructure/bmc/tpi-alpha")
            created += 1
        else:
            log_error(f"Failed to create TPI Alpha BMC secret: {stderr}")
    else:
        log_warn("Skipping TPI Alpha BMC (no value)")
        skipped += 1

    if secrets["TPI_BETA_BMC"]:
        log_info("Creating secret/fzymgc-house/infrastructure/bmc/tpi-beta...")
        exit_code, _, stderr = run_command(["vault", "kv", "put", "secret/fzymgc-house/infrastructure/bmc/tpi-beta", f"password={secrets['TPI_BETA_BMC']}"])
        if exit_code == 0:
            created_secrets.append("secret/fzymgc-house/infrastructure/bmc/tpi-beta")
            created += 1
        else:
            log_error(f"Failed to create TPI Beta BMC secret: {stderr}")
    else:
        log_warn("Skipping TPI Beta BMC (no value)")
        skipped += 1

    # Create Cloudflare secret
    if secrets["CLOUDFLARE_TOKEN"]:
        log_info("Creating secret/fzymgc-house/infrastructure/cloudflare/api-token...")
        exit_code, _, stderr = run_command(["vault", "kv", "put", "secret/fzymgc-house/infrastructure/cloudflare/api-token", f"token={secrets['CLOUDFLARE_TOKEN']}"])
        if exit_code == 0:
            created_secrets.append("secret/fzymgc-house/infrastructure/cloudflare/api-token")
            created += 1
        else:
            log_error(f"Failed to create Cloudflare secret: {stderr}")
    else:
        log_warn("Skipping Cloudflare API token (no value)")
        skipped += 1

    log_info(f"✓ Created {created} secrets, skipped {skipped}")
    print()
    log_warn("NOTE: Vault root token is NOT migrated to Vault (cannot store root token in Vault itself)")
    log_info("Developers must authenticate with their own Vault token that has the 'infrastructure-developer' policy")

    return created_secrets


def verify_secrets(created_secrets: list[str]) -> bool:
    """Verify that created secrets can be read from Vault"""
    log_step("Verifying secrets in Vault...")

    print()
    print("Secrets in Vault:")
    exit_code, stdout, _ = run_command(["vault", "kv", "list", "secret/fzymgc-house/infrastructure/"])
    if exit_code == 0:
        print(stdout)
    print()

    # Only verify if secrets were actually created
    if not created_secrets:
        log_warn("No secrets were created during migration (may already exist or no values found)")
        log_info("Skipping verification")
        return True

    # Test reading the first created secret to verify access
    test_secret = created_secrets[0]
    exit_code, _, stderr = run_command(["vault", "kv", "get", test_secret])

    if exit_code == 0:
        log_info("✓ Successfully verified secret access")
        return True
    else:
        log_error(f"Failed to read secrets from Vault: {stderr}")
        return False


def handle_ansible_vault(repo_root: Path) -> None:
    """Handle ansible-vault encrypted files"""
    log_step("Handling ansible-vault encrypted files...")

    ansible_vault_file = repo_root / "ansible" / "roles" / "k3sup" / "vars" / "main.yml"
    if ansible_vault_file.exists():
        print()
        log_warn(f"Found ansible-vault encrypted file: {ansible_vault_file}")
        print()
        print("To decrypt and view contents, run:")
        print("  cd ansible && ansible-vault view roles/k3sup/vars/main.yml")
        print()
        print("After viewing, manually create secrets in Vault with:")
        print("  vault kv put secret/fzymgc-house/infrastructure/k3sup/<name> <key>=<value>")
        print()
        input("Press Enter to continue...")


def main() -> int:
    """Main function"""
    print()
    log_info("==========================================")
    log_info("  Vault Secrets Migration Script")
    log_info("==========================================")
    print()

    # Change to repo root
    script_dir = Path(__file__).parent
    repo_root = script_dir.parent
    os.chdir(repo_root)

    # Run migration steps
    if not check_prerequisites():
        return 1

    if not check_vault_auth():
        return 1

    if not create_vault_policy(repo_root):
        return 1

    secrets = extract_secrets(repo_root)
    created_secrets = create_vault_secrets(secrets)

    if not verify_secrets(created_secrets):
        return 1

    handle_ansible_vault(repo_root)

    # Print summary
    print()
    log_info("==========================================")
    log_info("  Migration Complete!")
    log_info("==========================================")
    print()
    print("Summary:")
    print("  - Vault policy: infrastructure-developer created")
    print("  - Secrets migrated: Check output above for details")
    print("  - Secrets skipped: Check warnings above")
    print()
    print("Next steps:")
    print("  1. If secrets were skipped, manually add them to Vault:")
    print('     vault kv put secret/fzymgc-house/infrastructure/bmc/tpi-alpha password="..."')
    print("  2. Review docs/vault-migration.md for details")
    print("  3. Test with: cd ansible && ansible-playbook --check ...")
    print("  4. Developers need tokens with infrastructure-developer policy")
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
