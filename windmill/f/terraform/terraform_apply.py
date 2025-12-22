"""Apply Terraform changes."""

import os
import subprocess
from pathlib import Path


def main(
    module_dir: str,
    vault_addr: str = "https://vault.fzymgc.house",
    vault_token: str = "",
    tfc_token: str | None = None,
):
    """
    Apply Terraform plan.

    Args:
        module_dir: Path to Terraform module directory
        vault_addr: Vault server address
        vault_token: Vault authentication token
        tfc_token: Terraform Cloud API token (optional)

    Returns:
        dict with apply status and output
    """
    module_path = Path(module_dir)

    if not module_path.exists():
        raise ValueError(f"Module directory does not exist: {module_dir}")

    plan_file = module_path / "tfplan"
    if not plan_file.exists():
        raise ValueError(f"Plan file not found: {plan_file}")

    # Build environment with Vault config
    env = os.environ.copy()
    env["VAULT_ADDR"] = vault_addr
    env["VAULT_TOKEN"] = vault_token

    # Add TFC token if provided
    if tfc_token:
        env["TF_TOKEN_app_terraform_io"] = tfc_token

    # Apply the plan
    result = subprocess.run(
        ["terraform", "apply", "-no-color", "tfplan"],
        cwd=str(module_path),
        capture_output=True,
        text=True,
        env=env,
    )

    if result.returncode != 0:
        return {
            "module_dir": str(module_dir),
            "applied": False,
            "error": "Terraform apply failed",
            "stderr": result.stderr,
            "returncode": result.returncode,
        }

    return {"module_dir": str(module_dir), "applied": True, "output": result.stdout}
