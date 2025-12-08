"""Test Windmill configuration and integrations."""

import requests
import subprocess
from pathlib import Path
from typing import TypedDict


class discord_bot_configuration(TypedDict):
    application_id: str
    public_key: str


class c_discord_bot_token_configuration(TypedDict):
    token: str
    channel_id: str


class github(TypedDict):
    token: str


class s3(TypedDict):
    bucket: str
    region: str
    endPoint: str
    accessKey: str
    secretKey: str
    useSSL: bool
    pathStyle: bool


def main(
    discord: discord_bot_configuration,
    discord_bot_token: c_discord_bot_token_configuration,
    github: github,
    s3: s3,
):
    """
    Test all configured resources and integrations.

    Args:
        discord: Discord bot resource
        github: GitHub token resource
        s3: S3 storage resource

    Returns:
        dict with test results
    """
    results = {
        "discord": {"tested": False, "success": False, "error": None},
        "github": {"tested": False, "success": False, "error": None},
        "s3": {"tested": False, "success": False, "error": None},
    }

    # Test 1: Discord Bot
    try:
        payload = {
            "content": "✅ **Windmill Configuration Test**\n\nDiscord bot integration is working correctly!"
        }

        response = requests.post(
            f"https://discord.com/api/v10/channels/{discord_bot_token['channel_id']}/messages",
            headers={
                "Authorization": f"Bot {discord_bot_token['token']}",
                "Content-Type": "application/json",
            },
            json=payload,
            timeout=10,
        )

        results["discord"]["tested"] = True
        results["discord"]["success"] = response.ok
        if not response.ok:
            results["discord"]["error"] = (
                f"HTTP {response.status_code}: {response.text}"
            )
    except Exception as e:
        results["discord"]["tested"] = True
        results["discord"]["error"] = str(e)

    # Test 2: GitHub Token
    try:
        response = requests.get(
            "https://api.github.com/repos/fzymgc-house/selfhosted-cluster",
            headers={
                "Authorization": f"token {github['token']}",
                "Accept": "application/vnd.github.v3+json",
            },
            timeout=10,
        )

        results["github"]["tested"] = True
        results["github"]["success"] = response.ok
        if not response.ok:
            results["github"]["error"] = f"HTTP {response.status_code}: {response.text}"
    except Exception as e:
        results["github"]["tested"] = True
        results["github"]["error"] = str(e)

    # Test 3: S3 Storage (write test file)
    try:
        # Create a small test file
        test_file = Path("/tmp/windmill-s3-test.txt")
        test_file.write_text("Windmill S3 test")

        # Use AWS CLI to test S3 access
        env = {
            "AWS_ACCESS_KEY_ID": s3["accessKey"],
            "AWS_SECRET_ACCESS_KEY": s3["secretKey"],
            "AWS_DEFAULT_REGION": s3["region"],
        }

        result = subprocess.run(
            [
                "aws",
                "s3",
                "cp",
                str(test_file),
                f"s3://{s3['bucket']}/test/windmill-test.txt",
                "--endpoint-url",
                s3["endPoint"],
            ],
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )

        results["s3"]["tested"] = True
        results["s3"]["success"] = result.returncode == 0
        if result.returncode != 0:
            results["s3"]["error"] = result.stderr

        # Clean up test file
        test_file.unlink(missing_ok=True)
    except Exception as e:
        results["s3"]["tested"] = True
        results["s3"]["error"] = str(e)

    # Summary
    all_success = all(r["success"] for r in results.values() if r["tested"])

    # Finished
    return {
        "overall_success": all_success,
        "results": results,
        "summary": f"Discord: {'✅' if results['discord']['success'] else '❌'}, "
        f"GitHub: {'✅' if results['github']['success'] else '❌'}, "
        f"S3: {'✅' if results['s3']['success'] else '❌'}",
    }
