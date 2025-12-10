"""Send approval notification to Discord with Link buttons for Windmill resume/cancel."""

from datetime import datetime
from typing import TypedDict
from urllib.parse import urlparse, urlunparse

import requests
import wmill

# Discord API limits
DISCORD_EMBED_FIELD_LIMIT = 1000

# Public domain for Cloudflare Tunnel webhook endpoint
PUBLIC_WEBHOOK_DOMAIN = "windmill-wh.fzymgc.net"


class discord_bot_configuration(TypedDict):
    application_id: str
    public_key: str


class c_discord_bot_token_configuration(TypedDict):
    token: str
    channel_id: str


def make_public_url(internal_url: str) -> str:
    """
    Transform internal Windmill URL to public tunnel URL.

    Args:
        internal_url: Internal URL from Windmill (e.g., http://windmill.windmill.svc.cluster.local/api/...)

    Returns:
        Public HTTPS URL accessible via Cloudflare Tunnel
    """
    parsed = urlparse(internal_url)
    return urlunparse((
        'https',
        PUBLIC_WEBHOOK_DOMAIN,
        parsed.path,
        parsed.params,
        parsed.query,
        parsed.fragment
    ))


def main(discord: discord_bot_configuration, discord_bot_token: c_discord_bot_token_configuration, module: str, plan_summary: str, plan_details: str, run_id: str):
    """
    Send approval notification with Link buttons to Discord.

    Uses Windmill's built-in resume/cancel URLs exposed via Cloudflare Tunnel.
    Link buttons (style 5) open URLs directly - no Discord interactions endpoint needed.

    Args:
        discord: Discord bot configuration resource
        discord_bot_token: Discord bot token and channel configuration
        module: Terraform module name
        plan_summary: Short summary of plan changes
        plan_details: Full plan output
        run_id: Windmill run ID

    Returns:
        dict with message_id and notification status
    """
    # Get internal resume/cancel URLs from Windmill SDK
    urls = wmill.get_resume_urls()

    # Transform to public URLs via Cloudflare Tunnel
    public_resume = make_public_url(urls['resume'])
    public_cancel = make_public_url(urls['cancel'])

    # Truncate plan details to fit in Discord embed
    truncated_details = (
        plan_details[:DISCORD_EMBED_FIELD_LIMIT] + "..."
        if len(plan_details) > DISCORD_EMBED_FIELD_LIMIT
        else plan_details
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
                    {"name": "Run ID", "value": run_id, "inline": True},
                ],
                "timestamp": datetime.utcnow().isoformat(),
                "footer": {"text": "Windmill Terraform GitOps"},
            }
        ],
        "components": [
            {
                "type": 1,  # Action Row
                "components": [
                    {
                        "type": 2,  # Button
                        "style": 5,  # Link
                        "label": "✅ Approve",
                        "url": public_resume,
                    },
                    {
                        "type": 2,  # Button
                        "style": 5,  # Link
                        "label": "❌ Reject",
                        "url": public_cancel,
                    },
                    {
                        "type": 2,  # Button
                        "style": 5,  # Link
                        "label": "View Details",
                        "url": f"https://windmill.fzymgc.house/runs/{run_id}",
                    },
                ],
            }
        ],
    }

    response = requests.post(
        f"https://discord.com/api/v10/channels/{discord_bot_token['channel_id']}/messages",
        headers={"Authorization": f"Bot {discord_bot_token['token']}", "Content-Type": "application/json"},
        json=payload,
    )

    if not response.ok:
        raise Exception(f"Discord API failed: {response.status_code} - {response.text}")

    message = response.json()
    return {"message_id": message["id"], "notified": True}
