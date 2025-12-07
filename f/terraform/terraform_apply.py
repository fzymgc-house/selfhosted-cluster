"""Apply Terraform changes."""
import subprocess
from pathlib import Path


def main(
    module_dir: str,
    vault_addr: str = "https://vault.fzymgc.house",
    vault_token: str = ""
):
    """
    Apply Terraform plan.

    Args:
        module_dir: Path to Terraform module directory
        vault_addr: Vault server address
        vault_token: Vault authentication token

    Returns:
        dict with apply status and output
    """
    module_path = Path(module_dir)

    if not module_path.exists():
        raise ValueError(f"Module directory does not exist: {module_dir}")

    plan_file = module_path / "tfplan"
    if not plan_file.exists():
        raise ValueError(f"Plan file not found: {plan_file}")

    # Set environment variables for Vault
    env = {
        "VAULT_ADDR": vault_addr,
        "VAULT_TOKEN": vault_token,
        "PATH": "/usr/local/bin:/usr/bin:/bin"
    }

    # Apply the plan
    result = subprocess.run(
        ["terraform", "apply", "-no-color", "tfplan"],
        cwd=str(module_path),
        capture_output=True,
        text=True,
        env=env,
        check=True
    )

    return {
        "module_dir": str(module_dir),
        "applied": True,
        "output": result.stdout
    }
