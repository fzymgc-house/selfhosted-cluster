"""Run Terraform plan and store plan artifact in S3."""

import json
import os
import subprocess
from pathlib import Path
from typing import TypedDict

import boto3


class s3(TypedDict):
    bucket: str
    region: str
    endPoint: str
    accessKey: str
    secretKey: str


def main(
    module_dir: str,
    vault_addr: str = "https://vault.fzymgc.house",
    vault_token: str = "",
    tfc_token: str | None = None,
    s3_resource: s3 | None = None,
    job_id: str = "",
):
    """
    Run Terraform plan and optionally store plan in S3.

    Args:
        module_dir: Path to Terraform module directory
        vault_addr: Vault server address
        vault_token: Vault authentication token
        tfc_token: Terraform Cloud API token (optional)
        s3_resource: S3 resource for storing plan artifacts
        job_id: Unique job ID for plan storage key

    Returns:
        dict with plan summary, details, and S3 key if stored
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
    plan_file = module_path / "tfplan"
    result = subprocess.run(
        ["terraform", "plan", "-out=tfplan", "-json"],
        cwd=str(module_path),
        capture_output=True,
        text=True,
        env=env,
    )

    if result.returncode != 0:
        raise RuntimeError(f"Terraform plan failed (exit {result.returncode}):\n{result.stderr}")

    # Parse plan output
    plan_lines = result.stdout.strip().split("\n")
    changes = {"add": 0, "change": 0, "destroy": 0}

    for line in plan_lines:
        try:
            data = json.loads(line)
            if data.get("type") == "change_summary":
                raw_changes = data.get("changes", {})
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
        raise RuntimeError(f"Terraform show failed (exit {show_result.returncode}):\n{show_result.stderr}")

    plan_summary = f"Plan: {changes.get('add', 0)} to add, {changes.get('change', 0)} to change, {changes.get('destroy', 0)} to destroy"

    # Upload plan to S3 if resource provided
    plan_s3_key = None
    if s3_resource and job_id:
        # Sanitize module path for S3 key (replace / with -)
        module_key = module_dir.replace("/", "-").strip("-")
        plan_s3_key = f"terraform-plans/{module_key}/{job_id}/tfplan"

        s3_client = boto3.client(
            "s3",
            endpoint_url=s3_resource["endPoint"],
            aws_access_key_id=s3_resource["accessKey"],
            aws_secret_access_key=s3_resource["secretKey"],
            region_name=s3_resource.get("region", "auto"),
        )

        s3_client.upload_file(
            str(plan_file),
            s3_resource["bucket"],
            plan_s3_key,
        )

    return {
        "module_dir": str(module_dir),
        "plan_summary": plan_summary,
        "plan_details": show_result.stdout,
        "changes": changes,
        "has_changes": sum(changes.values()) > 0,
        "plan_s3_key": plan_s3_key,
    }
