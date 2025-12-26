"""Apply Terraform changes using plan from S3."""
# requirements:
# boto3

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
        dict with keys:
            - module_dir: Original module directory path
            - applied: Always True (function raises on failure)
            - output: Terraform apply stdout

    Note:
        S3 plan cleanup failures are logged but do not fail the apply.
    """
    module_path = Path(module_dir)

    if not module_path.exists():
        raise ValueError(f"Module directory does not exist: {module_dir}")

    plan_file = module_path / "tfplan"

    # Download plan from S3 if key provided
    s3_client = None
    if s3_resource and plan_s3_key:
        s3_client = _create_s3_client(s3_resource)

        try:
            s3_client.download_file(
                s3_resource["bucket"],
                plan_s3_key,
                str(plan_file),
            )
        except (ClientError, BotoCoreError) as e:
            raise RuntimeError(
                f"[S3 Download Error] Failed to download plan from S3: {e}\n"
                f"  Key: {plan_s3_key}\n"
                f"  Bucket: {s3_resource['bucket']}"
            )
        except OSError as e:
            raise RuntimeError(
                f"[Filesystem Error] Failed to write plan file: {e}\n"
                f"  Path: {plan_file}"
            )

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
    if s3_client and plan_s3_key:
        try:
            s3_client.delete_object(
                Bucket=s3_resource["bucket"],
                Key=plan_s3_key,
            )
        except (ClientError, BotoCoreError) as e:
            # Non-fatal: plan cleanup failure shouldn't fail the apply
            print(
                f"[S3 Cleanup Warning] Failed to clean up plan from S3 (non-fatal): {e}\n"
                f"  Key: {plan_s3_key}\n"
                f"  Consider setting S3 lifecycle policy to auto-expire old plans."
            )

    return {"module_dir": str(module_dir), "applied": True, "output": result.stdout}
