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


def _run_git(args: list[str], cwd: str | None = None, operation: str = "git operation") -> subprocess.CompletedProcess:
    """
    Run a git command with safe error handling.

    Raises RuntimeError with stderr on failure - never exposes the command line
    which may contain tokens in URLs.
    """
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        # Don't include args in error - may contain token in URL
        raise RuntimeError(f"Git {operation} failed (exit {result.returncode}):\n{result.stderr}")
    return result


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
        _run_git(["rm", "-rf", str(workspace_path)], operation="cleanup")

    repo_url = f"https://x-access-token:{github['token']}@github.com/{repository}.git"

    if is_commit_sha(branch):
        # For commit SHAs: clone default branch, then fetch and checkout the specific commit
        _run_git(["git", "clone", "--no-checkout", repo_url, str(workspace_path)], operation="clone")
        _run_git(["git", "-C", str(workspace_path), "fetch", "origin", branch], operation="fetch")
        _run_git(["git", "-C", str(workspace_path), "checkout", branch], operation="checkout")
    else:
        # For branch names/tags: use --branch with shallow clone
        _run_git(["git", "clone", "--branch", branch, "--depth", "1", repo_url, str(workspace_path)], operation="clone")

    # Get current commit SHA
    result = _run_git(["git", "-C", str(workspace_path), "rev-parse", "HEAD"], operation="rev-parse")
    commit_sha = result.stdout.strip()

    return {"workspace_path": str(workspace_path), "commit_sha": commit_sha, "repository": repository, "ref": branch}
