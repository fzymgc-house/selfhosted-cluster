"""Run Terraform plan and store plan artifact in S3."""
# requirements:
# boto3

import json
import os
import subprocess
from pathlib import Path
from typing import TypedDict

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError


class s3(TypedDict):
    bucket: str
    region: str
    endPoint: str
    accessKey: str
    secretKey: str
    useSSL: bool
    pathStyle: bool


def _create_s3_client(s3_resource: s3):
    """Create boto3 S3 client with proper configuration from Windmill resource."""
    addressing_style = "path" if s3_resource.get("pathStyle", True) else "virtual"
    return boto3.client(
        "s3",
        endpoint_url=s3_resource["endPoint"],
        aws_access_key_id=s3_resource["accessKey"],
        aws_secret_access_key=s3_resource["secretKey"],
        region_name=s3_resource.get("region", "auto"),
        use_ssl=s3_resource.get("useSSL", True),
        config=Config(s3={"addressing_style": addressing_style}),
    )


def _sanitize_module_path(module_dir: str) -> str:
    """Sanitize module path for S3 key to prevent collisions.

    Uses '--' as separator to distinguish from literal hyphens in paths.
    Example: 'tf/vault' -> 'tf--vault', 'tf-core/services' -> 'tf-core--services'
    """
    return module_dir.replace("/", "--").strip("-")


def main(
    module_dir: str,
    vault_addr: str = "https://vault.fzymgc.house",
    vault_token: str = "",
    tfc_token: str | None = None,
    s3_resource: s3 | None = None,
):
    """
    Run Terraform plan and optionally store plan in S3.

    Uses Windmill's WM_JOB_ID environment variable for unique plan storage.
    S3 storage is skipped if s3_resource is not provided or WM_JOB_ID is not set.

    Args:
        module_dir: Path to Terraform module directory
        vault_addr: Vault server address
        vault_token: Vault authentication token
        tfc_token: Terraform Cloud API token (optional)
        s3_resource: S3 resource for storing plan artifacts

    Returns:
        dict with keys:
            - module_dir: Original module directory path
            - plan_summary: Human-readable summary (e.g., "Plan: 1 to add, 0 to change, 0 to destroy")
            - plan_details: Full terraform show output
            - changes: dict with add/change/destroy counts
            - has_changes: bool indicating if any resources will change
            - plan_s3_key: S3 key where plan is stored (None if S3 not configured)
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

    # Upload plan to S3 if resource provided and WM_JOB_ID is set
    plan_s3_key = None
    job_id = os.environ.get("WM_JOB_ID", "")
    if s3_resource and job_id:
        module_key = _sanitize_module_path(module_dir)
        plan_s3_key = f"terraform-plans/{module_key}/{job_id}/tfplan"
        s3_client = _create_s3_client(s3_resource)

        try:
            s3_client.upload_file(
                str(plan_file),
                s3_resource["bucket"],
                plan_s3_key,
            )
        except (ClientError, BotoCoreError) as e:
            raise RuntimeError(
                f"[S3 Upload Error] Terraform plan succeeded but failed to upload to S3: {e}\n"
                f"  Key: {plan_s3_key}\n"
                f"  Bucket: {s3_resource['bucket']}"
            )

    return {
        "module_dir": str(module_dir),
        "plan_summary": plan_summary,
        "plan_details": show_result.stdout,
        "changes": changes,
        "has_changes": sum(changes.values()) > 0,
        "plan_s3_key": plan_s3_key,
    }
