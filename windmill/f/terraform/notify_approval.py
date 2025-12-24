"""Send approval notification to Discord with Link buttons for Windmill approval workflow."""  # noqa: INP001
# requirements:
# wmill
# requests

import logging
import os
from datetime import UTC, datetime
from typing import TypedDict
from urllib.parse import urlparse, urlunparse

import requests
import wmill

# Configure logging for Windmill
logger = logging.getLogger(__name__)

# Discord API limits
DISCORD_EMBED_FIELD_LIMIT = 1000
DISCORD_API_TIMEOUT = 30  # seconds

# Public domain for Cloudflare Tunnel webhook endpoint
PUBLIC_WEBHOOK_DOMAIN = "windmill-wh.fzymgc.net"


class discord_bot_configuration(TypedDict):  # noqa: N801
    """Discord bot configuration resource type (name matches Windmill resource)."""

    application_id: str
    public_key: str


class c_discord_bot_token_configuration(TypedDict):  # noqa: N801
    """Discord bot token configuration resource type (name matches Windmill resource)."""

    token: str
    channel_id: str


def make_public_url(internal_url: str) -> str:
    """Transform internal Windmill URL to public tunnel URL.

    Args:
        internal_url: Internal URL from Windmill (e.g., http://windmill.windmill.svc.cluster.local/api/...)

    Returns:
        Public HTTPS URL accessible via Cloudflare Tunnel

    """
    if not isinstance(internal_url, str):
        msg = f"Expected string URL, got {type(internal_url).__name__}: {internal_url}"
        raise TypeError(msg)

    parsed = urlparse(internal_url)
    return urlunparse(
        (
            "https",
            PUBLIC_WEBHOOK_DOMAIN,
            parsed.path,
            parsed.params,
            parsed.query,
            parsed.fragment,
        ),
    )


def main(
    discord: discord_bot_configuration,  # noqa: ARG001 - Required by Windmill resource injection
    discord_bot_token: c_discord_bot_token_configuration,
    module: str,
    plan_summary: str,
    plan_details: str,
) -> dict[str, str | bool]:
    """Send approval notification with Link buttons to Discord.

    Uses Windmill's built-in approval page and resume/cancel URLs exposed via Cloudflare Tunnel.
    Link buttons (style 5) open URLs directly - no Discord interactions endpoint needed.

    Buttons provided:
    - Review & Approve: Opens Windmill approval page with proper UI (recommended)
    - Quick Approve: Opens resume URL directly (browser displays raw API JSON response)
    - Reject: Opens cancel URL directly (browser displays raw API JSON response)
    - Run Details: Opens Windmill run page to see flow status (omitted if run_id unavailable)

    Note: Quick Approve and Reject open API URLs directly, showing JSON responses.
    Use "Review & Approve" for a proper UI experience.

    Args:
        discord: Discord bot configuration resource
        discord_bot_token: Discord bot token and channel configuration
        module: Terraform module name
        plan_summary: Short summary of plan changes
        plan_details: Full plan output

    Returns:
        dict with message_id and notification status

    """
    # Get flow job ID and workspace from Windmill environment variables
    run_id = os.environ.get("WM_FLOW_JOB_ID") or os.environ.get("WM_JOB_ID")
    workspace = os.environ.get("WM_WORKSPACE", "terraform-gitops")

    if not run_id:
        logger.warning("No WM_FLOW_JOB_ID or WM_JOB_ID found, Run Details button will be omitted")

    logger.info("Sending approval notification for module %s to channel %s", module, discord_bot_token["channel_id"])

    # Get internal resume/cancel/approval URLs from Windmill SDK
    try:
        urls = wmill.get_resume_urls()
    except Exception as e:
        msg = f"Failed to get resume URLs from Windmill SDK: {e}"
        raise RuntimeError(msg) from e

    if not urls or "resume" not in urls or "cancel" not in urls:
        msg = f"Invalid resume URLs returned: {urls}"
        raise ValueError(msg)

    # Transform to public URLs via Cloudflare Tunnel
    public_resume = make_public_url(urls["resume"])
    public_cancel = make_public_url(urls["cancel"])
    # Approval page URL may be available from SDK; fall back to resume URL if not present
    # (approvalPage provides a proper UI vs raw API JSON response)
    public_approval_page = make_public_url(urls.get("approvalPage", urls["resume"]))

    # Truncate plan details to fit in Discord embed
    truncated_details = plan_details[:DISCORD_EMBED_FIELD_LIMIT] + "..." if len(plan_details) > DISCORD_EMBED_FIELD_LIMIT else plan_details

    # Build button components
    buttons = [
        {
            "type": 2,  # Button
            "style": 5,  # Link
            "label": "🔍 Review & Approve",
            "url": public_approval_page,
        },
        {
            "type": 2,  # Button
            "style": 5,  # Link
            "label": "⏩ Quick Approve",
            "url": public_resume,
        },
        {
            "type": 2,  # Button
            "style": 5,  # Link
            "label": "❌ Reject",
            "url": public_cancel,
        },
    ]

    # Only add Run Details button if we have a valid run_id
    if run_id:
        # Windmill run page URL format: /{workspace}/runs/{job_id}
        buttons.append(
            {
                "type": 2,  # Button
                "style": 5,  # Link
                "label": "📋 Run Details",
                "url": f"https://windmill.fzymgc.house/{workspace}/runs/{run_id}",
            },
        )

    payload = {
        "embeds": [
            {
                "title": "🚨 Terraform Apply Approval Required",
                "description": f"Module: **{module}**",
                "color": 0xFFA500,  # Orange
                "fields": [
                    {"name": "Plan Summary", "value": f"```\n{plan_summary}\n```", "inline": False},
                    {"name": "Plan Details", "value": f"```terraform\n{truncated_details}\n```", "inline": False},
                    {"name": "Run ID", "value": run_id or "unavailable", "inline": True},
                ],
                "timestamp": datetime.now(UTC).isoformat(),
                "footer": {"text": "Windmill Terraform GitOps"},
            },
        ],
        "components": [
            {
                "type": 1,  # Action Row
                "components": buttons,
            },
        ],
    }

    # Send Discord message with proper error handling for network issues
    try:
        response = requests.post(
            f"https://discord.com/api/v10/channels/{discord_bot_token['channel_id']}/messages",
            headers={"Authorization": f"Bot {discord_bot_token['token']}", "Content-Type": "application/json"},
            json=payload,
            timeout=DISCORD_API_TIMEOUT,
        )
    except requests.exceptions.Timeout:
        msg = f"Discord API request timed out after {DISCORD_API_TIMEOUT}s"
        raise RuntimeError(msg) from None
    except requests.exceptions.RequestException as e:
        msg = f"Failed to send Discord notification: {e}"
        raise RuntimeError(msg) from e

    if not response.ok:
        msg = f"Discord API failed: {response.status_code} - {response.text}"
        raise RuntimeError(msg)

    # Parse response with error handling for malformed JSON
    try:
        message = response.json()
    except (requests.exceptions.JSONDecodeError, ValueError) as e:
        msg = f"Discord returned invalid JSON response: {response.text[:200]}"
        raise RuntimeError(msg) from e

    # Validate expected response structure
    message_id = message.get("id")
    if not message_id:
        msg = f"Discord response missing 'id' field: {message}"
        raise RuntimeError(msg)

    logger.info("Discord notification sent successfully, message_id=%s", message_id)
    return {"message_id": message_id, "notified": True}
