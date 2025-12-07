"""Send approval notification to Discord."""
import requests
from datetime import datetime
from typing import TypedDict


class DiscordBotResource(TypedDict):
    bot_token: str
    application_id: str
    public_key: str
    channel_id: str


def main(
    discord: DiscordBotResource,
    module: str,
    plan_summary: str,
    plan_details: str,
    run_id: str
):
    """
    Send approval notification with interactive buttons to Discord.

    Args:
        discord: Discord bot resource
        module: Terraform module name
        plan_summary: Short summary of plan changes
        plan_details: Full plan output
        run_id: Windmill run ID

    Returns:
        dict with message_id and notification status
    """
    # Truncate plan details to fit in Discord embed
    truncated_details = plan_details[:1000] + "..." if len(plan_details) > 1000 else plan_details

    payload = {
        "embeds": [{
            "title": "🚨 Terraform Apply Approval Required",
            "description": f"Module: **{module}**",
            "color": 0xFFA500,  # Orange
            "fields": [
                {
                    "name": "Plan Summary",
                    "value": f"```\n{plan_summary}\n```",
                    "inline": False
                },
                {
                    "name": "Plan Details",
                    "value": f"```terraform\n{truncated_details}\n```",
                    "inline": False
                },
                {
                    "name": "Run ID",
                    "value": run_id,
                    "inline": True
                }
            ],
            "timestamp": datetime.utcnow().isoformat(),
            "footer": {
                "text": "Windmill Terraform GitOps"
            }
        }],
        "components": [{
            "type": 1,  # Action Row
            "components": [
                {
                    "type": 2,  # Button
                    "style": 3,  # Success (green)
                    "label": "✅ Approve",
                    "custom_id": f"approve_{run_id}"
                },
                {
                    "type": 2,  # Button
                    "style": 4,  # Danger (red)
                    "label": "❌ Reject",
                    "custom_id": f"reject_{run_id}"
                },
                {
                    "type": 2,  # Button
                    "style": 5,  # Link
                    "label": "View Details",
                    "url": f"https://windmill.fzymgc.house/runs/{run_id}"
                }
            ]
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

    message = response.json()
    return {
        "message_id": message["id"],
        "notified": True
    }
