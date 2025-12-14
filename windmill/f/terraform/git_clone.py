"""Clone Git repository for Terraform operations."""

import re
import subprocess
from pathlib import Path
from typing import TypedDict


class github(TypedDict):
    token: str


def is_commit_sha(ref: str) -> bool:
    """Check if ref looks like a commit SHA (40 hex characters)."""
    return bool(re.match(r"^[0-9a-f]{40}$", ref.lower()))


def main(github: github, repository: str = "fzymgc-house/selfhosted-cluster", branch: str = "main", workspace_dir: str = "/tmp/terraform-workspace"):
    """
    Clone Git repository at a specific ref (branch, tag, or commit SHA).

    Args:
        github: GitHub resource with token
        repository: Repository in format "owner/repo"
        branch: Git ref to checkout (branch name, tag, or commit SHA)
        workspace_dir: Directory to clone into

    Returns:
        dict with workspace_path and commit_sha
    """
    # Clean up existing workspace
    workspace_path = Path(workspace_dir)
    if workspace_path.exists():
        subprocess.run(["rm", "-rf", str(workspace_path)], check=True)

    repo_url = f"https://x-access-token:{github['token']}@github.com/{repository}.git"

    if is_commit_sha(branch):
        # For commit SHAs: clone default branch, then fetch and checkout the specific commit
        subprocess.run(["git", "clone", "--no-checkout", repo_url, str(workspace_path)], check=True, capture_output=True, text=True)
        subprocess.run(["git", "-C", str(workspace_path), "fetch", "origin", branch], check=True, capture_output=True, text=True)
        subprocess.run(["git", "-C", str(workspace_path), "checkout", branch], check=True, capture_output=True, text=True)
    else:
        # For branch names/tags: use --branch with shallow clone
        subprocess.run(["git", "clone", "--branch", branch, "--depth", "1", repo_url, str(workspace_path)], check=True, capture_output=True, text=True)

    # Get current commit SHA
    result = subprocess.run(["git", "-C", str(workspace_path), "rev-parse", "HEAD"], check=True, capture_output=True, text=True)
    commit_sha = result.stdout.strip()

    return {"workspace_path": str(workspace_path), "commit_sha": commit_sha, "repository": repository, "ref": branch}
