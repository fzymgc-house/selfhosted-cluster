"""Initialize Terraform workspace."""

import os
import re
import subprocess
from pathlib import Path
from typing import Optional, TypedDict


class s3(TypedDict):
    bucket: str
    region: str
    endPoint: str
    accessKey: str
    secretKey: str
    useSSL: bool
    pathStyle: bool


def _uses_terraform_cloud(module_dir: Path) -> bool:
    """
    Check if module uses Terraform Cloud backend.

    Scans .tf files for 'cloud {' block which indicates TFC configuration.
    """
    for tf_file in module_dir.glob("*.tf"):
        content = tf_file.read_text()
        # Match 'cloud {' or 'cloud{' in terraform block
        if re.search(r'\bcloud\s*\{', content):
            return True
    return False


def main(
    workspace_path: str,
    module_path: str,
    s3: Optional[s3] = None,
    s3_bucket_prefix: str = "",
    tfc_token: Optional[str] = None,
):
    """
    Initialize Terraform module.

    Supports both S3 backend and Terraform Cloud configurations.
    Automatically detects which backend type the module uses.

    Args:
        workspace_path: Path to cloned repository
        module_path: Relative path to Terraform module (e.g., "tf/vault")
        s3: S3 resource for state storage (optional, for S3 backend)
        s3_bucket_prefix: Optional prefix path within the bucket
        tfc_token: Terraform Cloud API token (optional, for TFC backend)

    Returns:
        dict with init status and module info
    """
    module_dir = Path(workspace_path) / module_path

    if not module_dir.exists():
        raise ValueError(f"Module directory does not exist: {module_dir}")

    uses_tfc = _uses_terraform_cloud(module_dir)
    env = os.environ.copy()

    if uses_tfc:
        # Terraform Cloud configuration
        if not tfc_token:
            raise ValueError(
                f"Terraform Cloud token required for module {module_path}. "
                "Set the tfc_token parameter or g/all/tfc_token variable."
            )
        env["TF_TOKEN_app_terraform_io"] = tfc_token
        cmd = ["terraform", "init"]
        backend_type = "terraform_cloud"
    else:
        # S3 backend configuration
        if not s3:
            raise ValueError("S3 configuration required for non-Terraform Cloud modules")

        prefix = s3_bucket_prefix.strip("/") if s3_bucket_prefix else ""
        state_key = (
            f"{prefix}/terraform/{module_path}/terraform.tfstate"
            if prefix
            else f"terraform/{module_path}/terraform.tfstate"
        )

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
            "-backend-config=use_path_style=false",
        ]
        cmd = ["terraform", "init"] + backend_config
        backend_type = "s3"

    result = subprocess.run(cmd, cwd=str(module_dir), capture_output=True, text=True, env=env, check=True)

    return {
        "module_path": module_path,
        "module_dir": str(module_dir),
        "initialized": True,
        "backend_type": backend_type,
        "output": result.stdout,
    }
