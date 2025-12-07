"""Clone Git repository for Terraform operations."""
import subprocess
import os
from pathlib import Path
from typing import TypedDict


class GithubResource(TypedDict):
    token: str


def main(
    github: GithubResource,
    repository: str = "fzymgc-house/selfhosted-cluster",
    branch: str = "main",
    workspace_dir: str = "/tmp/terraform-workspace"
):
    """
    Clone Git repository.

    Args:
        github: GitHub resource with token
        repository: Repository in format "owner/repo"
        branch: Branch to clone
        workspace_dir: Directory to clone into

    Returns:
        dict with workspace_path and commit_sha
    """
    # Clean up existing workspace
    workspace_path = Path(workspace_dir)
    if workspace_path.exists():
        subprocess.run(["rm", "-rf", str(workspace_path)], check=True)

    # Clone repository
    repo_url = f"https://x-access-token:{github['token']}@github.com/{repository}.git"

    subprocess.run([
        "git", "clone",
        "--branch", branch,
        "--depth", "1",
        repo_url,
        str(workspace_path)
    ], check=True, capture_output=True, text=True)

    # Get current commit SHA
    result = subprocess.run(
        ["git", "-C", str(workspace_path), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True
    )
    commit_sha = result.stdout.strip()

    return {
        "workspace_path": str(workspace_path),
        "commit_sha": commit_sha,
        "repository": repository,
        "branch": branch
    }
