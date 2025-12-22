"""Run Terraform plan."""

import json
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
    Run Terraform plan.

    Args:
        module_dir: Path to Terraform module directory
        vault_addr: Vault server address
        vault_token: Vault authentication token
        tfc_token: Terraform Cloud API token (optional)

    Returns:
        dict with plan summary and details
    """
    module_path = Path(module_dir)

    if not module_path.exists():
        raise ValueError(f"Module directory does not exist: {module_dir}")

    # Build environment with Vault config
    env = os.environ.copy()
    env["VAULT_ADDR"] = vault_addr
    env["VAULT_TOKEN"] = vault_token

    # Add TFC token if provided
    if tfc_token:
        env["TF_TOKEN_app_terraform_io"] = tfc_token

    # Run terraform plan with JSON output
    result = subprocess.run(
        ["terraform", "plan", "-out=tfplan", "-json"],
        cwd=str(module_path),
        capture_output=True,
        text=True,
        env=env,
    )

    if result.returncode != 0:
        return {
            "module_dir": str(module_dir),
            "error": "Terraform plan failed",
            "stderr": result.stderr,
            "returncode": result.returncode,
        }

    # Parse plan output
    plan_lines = result.stdout.strip().split("\n")
    changes = {"add": 0, "change": 0, "destroy": 0}

    for line in plan_lines:
        try:
            data = json.loads(line)
            if data.get("type") == "change_summary":
                raw_changes = data.get("changes", {})
                # Ensure values are integers (Terraform JSON may return strings)
                changes = {
                    "add": int(raw_changes.get("add", 0)),
                    "change": int(raw_changes.get("change", 0)),
                    "destroy": int(raw_changes.get("destroy", 0)),
                }
        except json.JSONDecodeError:
            continue

    # Get human-readable plan
    show_result = subprocess.run(
        ["terraform", "show", "-no-color", "tfplan"],
        cwd=str(module_path),
        capture_output=True,
        text=True,
        env=env,
    )

    if show_result.returncode != 0:
        return {
            "module_dir": str(module_dir),
            "error": "Terraform show failed",
            "stderr": show_result.stderr,
            "returncode": show_result.returncode,
        }

    plan_summary = f"Plan: {changes.get('add', 0)} to add, {changes.get('change', 0)} to change, {changes.get('destroy', 0)} to destroy"

    return {
        "module_dir": str(module_dir),
        "plan_summary": plan_summary,
        "plan_details": show_result.stdout,
        "changes": changes,
        "has_changes": sum(changes.values()) > 0,
    }
