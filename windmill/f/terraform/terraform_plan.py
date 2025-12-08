"""Run Terraform plan."""

import json
import subprocess
from pathlib import Path


def main(module_dir: str, vault_addr: str = "https://vault.fzymgc.house", vault_token: str = ""):
    """
    Run Terraform plan.

    Args:
        module_dir: Path to Terraform module directory
        vault_addr: Vault server address
        vault_token: Vault authentication token

    Returns:
        dict with plan summary and details
    """
    module_path = Path(module_dir)

    if not module_path.exists():
        raise ValueError(f"Module directory does not exist: {module_dir}")

    # Set environment variables for Vault
    env = {"VAULT_ADDR": vault_addr, "VAULT_TOKEN": vault_token, "PATH": "/usr/local/bin:/usr/bin:/bin"}

    # Run terraform plan with JSON output
    result = subprocess.run(["terraform", "plan", "-out=tfplan", "-json"], cwd=str(module_path), capture_output=True, text=True, env=env, check=True)

    # Parse plan output
    plan_lines = result.stdout.strip().split("\n")
    changes = {"add": 0, "change": 0, "destroy": 0}

    for line in plan_lines:
        try:
            data = json.loads(line)
            if data.get("type") == "change_summary":
                changes = data.get("changes", changes)
        except json.JSONDecodeError:
            continue

    # Get human-readable plan
    show_result = subprocess.run(["terraform", "show", "-no-color", "tfplan"], cwd=str(module_path), capture_output=True, text=True, env=env, check=True)

    plan_summary = f"Plan: {changes.get('add', 0)} to add, {changes.get('change', 0)} to change, {changes.get('destroy', 0)} to destroy"

    return {"module_dir": str(module_dir), "plan_summary": plan_summary, "plan_details": show_result.stdout, "changes": changes, "has_changes": sum(changes.values()) > 0}
