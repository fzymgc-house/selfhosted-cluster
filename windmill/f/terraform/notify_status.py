"""Send status notification to Discord."""
import requests
from datetime import datetime


def main(
    discord: dict,
    module: str,
    status: str,
    details: str
):
    """
    Send status notification to Discord.

    Args:
        discord: Discord bot resource
        module: Terraform module name
        status: Status ("success" or "failed")
        details: Status details/message

    Returns:
        dict with notification status
    """
    config = {
        "success": {
            "title": "✅ Terraform Apply Complete",
            "color": 0x00FF00  # Green
        },
        "failed": {
            "title": "❌ Terraform Apply Failed",
            "color": 0xFF0000  # Red
        }
    }

    status_config = config.get(status, config["failed"])

    # Truncate details to fit in Discord
    truncated_details = details[:1000] + "..." if len(details) > 1000 else details

    payload = {
        "embeds": [{
            "title": status_config["title"],
            "description": f"Module: **{module}**",
            "color": status_config["color"],
            "fields": [{
                "name": "Details",
                "value": f"```\n{truncated_details}\n```",
                "inline": False
            }],
            "timestamp": datetime.utcnow().isoformat(),
            "footer": {
                "text": "Windmill Terraform GitOps"
            }
        }]
    }

    response = requests.post(
        f"https://discord.com/api/v10/channels/{discord['channel_id']}/messages",
        headers={
            "Authorization": f"Bot {discord['bot_token']}",
            "Content-Type": "application/json"
        },
        json=payload
    )

    if not response.ok:
        raise Exception(f"Discord API failed: {response.status_code} - {response.text}")

    return {"notified": True}
