"""Apply Terraform changes using plan from S3."""

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
    plan_s3_key: str = "",
):
    """
    Apply Terraform plan, downloading from S3 if key provided.

    Args:
        module_dir: Path to Terraform module directory
        vault_addr: Vault server address
        vault_token: Vault authentication token
        tfc_token: Terraform Cloud API token (optional)
        s3_resource: S3 resource for retrieving plan artifacts
        plan_s3_key: S3 key where plan file is stored

    Returns:
        dict with apply status and output
    """
    module_path = Path(module_dir)

    if not module_path.exists():
        raise ValueError(f"Module directory does not exist: {module_dir}")

    plan_file = module_path / "tfplan"

    # Download plan from S3 if key provided
    if s3_resource and plan_s3_key:
        s3_client = boto3.client(
            "s3",
            endpoint_url=s3_resource["endPoint"],
            aws_access_key_id=s3_resource["accessKey"],
            aws_secret_access_key=s3_resource["secretKey"],
            region_name=s3_resource.get("region", "auto"),
        )

        try:
            s3_client.download_file(
                s3_resource["bucket"],
                plan_s3_key,
                str(plan_file),
            )
        except Exception as e:
            raise RuntimeError(f"Failed to download plan from S3 ({plan_s3_key}): {e}")

    # Verify plan file exists
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
        raise RuntimeError(f"Terraform apply failed (exit {result.returncode}):\n{result.stderr}")

    # Clean up plan from S3 after successful apply
    if s3_resource and plan_s3_key:
        try:
            s3_client.delete_object(
                Bucket=s3_resource["bucket"],
                Key=plan_s3_key,
            )
        except Exception:
            # Non-fatal: plan cleanup failure shouldn't fail the apply
            pass

    return {"module_dir": str(module_dir), "applied": True, "output": result.stdout}
