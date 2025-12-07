"""Initialize Terraform workspace."""
import subprocess
import os
from pathlib import Path
from typing import TypedDict


class s3(TypedDict):
    bucket: str
    region: str
    endPoint: str
    accessKey: str
    secretKey: str
    useSSL: bool
    pathStyle: bool


def main(
    workspace_path: str,
    module_path: str,
    s3: s3,
    s3_bucket_prefix: str = ""
):
    """
    Initialize Terraform module.

    Args:
        workspace_path: Path to cloned repository
        module_path: Relative path to Terraform module (e.g., "tf/vault")
        s3: S3 resource for state storage
        s3_bucket_prefix: Optional prefix path within the bucket (e.g., "windmill/terraform-gitops")

    Returns:
        dict with init status and module info
    """
    module_dir = Path(workspace_path) / module_path

    if not module_dir.exists():
        raise ValueError(f"Module directory does not exist: {module_dir}")

    # Configure backend with bucket prefix
    # Prefix allows sharing a bucket with other services
    prefix = s3_bucket_prefix.strip('/') if s3_bucket_prefix else ""
    state_key = f"{prefix}/terraform/{module_path}/terraform.tfstate" if prefix else f"terraform/{module_path}/terraform.tfstate"

    backend_config = [
        f"-backend-config=bucket={s3['bucket']}",
        f"-backend-config=key={state_key}",
        f"-backend-config=region={s3['region']}",
        f"-backend-config=endpoint={s3['endPoint']}",
        f"-backend-config=access_key={s3['accessKey']}",
        f"-backend-config=secret_key={s3['secretKey']}",
        "-backend-config=skip_credentials_validation=true",
        "-backend-config=skip_metadata_api_check=true",
        "-backend-config=skip_region_validation=true",
        "-backend-config=use_path_style=false"
    ]

    # Run terraform init
    cmd = ["terraform", "init"] + backend_config
    result = subprocess.run(
        cmd,
        cwd=str(module_dir),
        capture_output=True,
        text=True,
        check=True
    )

    return {
        "module_path": module_path,
        "module_dir": str(module_dir),
        "initialized": True,
        "output": result.stdout
    }
