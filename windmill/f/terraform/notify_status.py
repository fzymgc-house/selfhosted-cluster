"""Send status notification to Discord and update approval message."""

from datetime import datetime
from typing import Optional, TypedDict

import requests

# Discord API limits
DISCORD_EMBED_FIELD_LIMIT = 1000


class discord_bot_configuration(TypedDict):
    application_id: str
    public_key: str


class c_discord_bot_token_configuration(TypedDict):
    token: str
    channel_id: str


def main(
    discord: discord_bot_configuration,
    discord_bot_token: c_discord_bot_token_configuration,
    module: str,
    status: str,
    details: str,
    approval_message_id: Optional[str] = None,
):
    """
    Send status notification to Discord and optionally update the approval message.

    Args:
        discord: Discord bot configuration resource
        discord_bot_token: Discord bot token and channel configuration
        module: Terraform module name
        status: Status ("success" or "failed")
        details: Status details/message
        approval_message_id: Optional message ID of the approval notification to update

    Returns:
        dict with notification status
    """
    config = {
        "success": {
            "title": "✅ Terraform Apply Complete",
            "color": 0x00FF00,  # Green
            "approval_title": "✅ Terraform Apply Approved & Complete",
            "approval_status": "Approved and applied successfully",
        },
        "failed": {
            "title": "❌ Terraform Apply Failed",
            "color": 0xFF0000,  # Red
            "approval_title": "⚠️ Terraform Apply Failed",
            "approval_status": "Approved but apply failed",
        },
    }

    status_config = config.get(status, config["failed"])

    # Truncate details to fit in Discord
    truncated_details = (
        details[:DISCORD_EMBED_FIELD_LIMIT] + "..."
        if len(details) > DISCORD_EMBED_FIELD_LIMIT
        else details
    )

    # Send new status notification
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

    # Update original approval message if provided
    if approval_message_id:
        _update_approval_message(
            discord_bot_token=discord_bot_token,
            message_id=approval_message_id,
            title=status_config["approval_title"],
            status_text=status_config["approval_status"],
            details=truncated_details,
            color=status_config["color"],
            module=module,
        )

    return {"notified": True}


def _update_approval_message(
    discord_bot_token: c_discord_bot_token_configuration,
    message_id: str,
    title: str,
    status_text: str,
    details: str,
    color: int,
    module: str,
) -> None:
    """
    Update original approval message with final status.

    Removes buttons and updates embed to show completion status.
    Ignores 404 errors (message was deleted).

    Args:
        discord_bot_token: Discord bot token and channel configuration
        message_id: Original message ID to update
        title: New message title
        status_text: Status message
        details: Status details
        color: Discord embed color
        module: Terraform module name
    """
    edit_payload = {
        "embeds": [
            {
                "title": title,
                "description": f"Module: **{module}**",
                "color": color,
                "fields": [
                    {"name": "Status", "value": status_text, "inline": False},
                    {"name": "Details", "value": f"```\n{details}\n```", "inline": False},
                ],
                "timestamp": datetime.utcnow().isoformat(),
                "footer": {"text": "Windmill Terraform GitOps"},
            }
        ],
        "components": [],  # Remove buttons
    }

    response = requests.patch(
        f"https://discord.com/api/v10/channels/{discord_bot_token['channel_id']}/messages/{message_id}",
        headers={"Authorization": f"Bot {discord_bot_token['token']}", "Content-Type": "application/json"},
        json=edit_payload,
    )

    # Ignore 404 (message deleted), raise other errors
    if not response.ok and response.status_code != 404:
        raise Exception(f"Discord API failed to update message: {response.status_code} - {response.text}")
