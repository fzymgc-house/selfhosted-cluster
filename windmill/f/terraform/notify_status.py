"""Send status notification to Discord."""

from datetime import datetime
from typing import TypedDict

import requests


class discord_bot_configuration(TypedDict):
    application_id: str
    public_key: str


class c_discord_bot_token_configuration(TypedDict):
    token: str
    channel_id: str


def main(discord: discord_bot_configuration, discord_bot_token: c_discord_bot_token_configuration, module: str, status: str, details: str):
    """
    Send status notification to Discord.

    Args:
        discord: Discord bot configuration resource
        discord_bot_token: Discord bot token and channel configuration
        module: Terraform module name
        status: Status ("success" or "failed")
        details: Status details/message

    Returns:
        dict with notification status
    """
    config = {
        "success": {
            "title": "✅ Terraform Apply Complete",
            "color": 0x00FF00,  # Green
        },
        "failed": {
            "title": "❌ Terraform Apply Failed",
            "color": 0xFF0000,  # Red
        },
    }

    status_config = config.get(status, config["failed"])

    # Truncate details to fit in Discord
    truncated_details = details[:1000] + "..." if len(details) > 1000 else details

    payload = {
        "embeds": [
            {
                "title": status_config["title"],
                "description": f"Module: **{module}**",
                "color": status_config["color"],
                "fields": [{"name": "Details", "value": f"```\n{truncated_details}\n```", "inline": False}],
                "timestamp": datetime.utcnow().isoformat(),
                "footer": {"text": "Windmill Terraform GitOps"},
            }
        ]
    }

    response = requests.post(
        f"https://discord.com/api/v10/channels/{discord_bot_token['channel_id']}/messages",
        headers={"Authorization": f"Bot {discord_bot_token['token']}", "Content-Type": "application/json"},
        json=payload,
    )

    if not response.ok:
        raise Exception(f"Discord API failed: {response.status_code} - {response.text}")

    return {"notified": True}
