# HCP Terraform to Discord webhook transformer
# Python Worker using Cloudflare Workers Python runtime

import hmac
import hashlib
import json
import re
from datetime import datetime, timezone
from urllib.parse import urlparse

import httpx
from workers import Request, Response


def sanitize_for_discord(text: str | None) -> str:
    """Escape Discord markdown characters to prevent injection."""
    if not isinstance(text, str):
        return ""
    # Escape Discord markdown: * _ ` ~ | [ ] ( ) > #
    return re.sub(r'([*_`~|[\]()>#])', r'\\\1', text)


def is_valid_terraform_url(url: str | None) -> bool:
    """Validate URL is from trusted HCP Terraform domain."""
    if not isinstance(url, str):
        return False
    try:
        parsed = urlparse(url)
        return parsed.hostname == "app.terraform.io"
    except Exception:
        return False


def verify_hmac(body: str, signature: str, secret: str) -> bool:
    """Verify HMAC-SHA512 signature from HCP Terraform."""
    computed = hmac.new(
        secret.encode('utf-8'),
        body.encode('utf-8'),
        hashlib.sha512
    ).hexdigest()
    return hmac.compare_digest(computed, signature)


async def on_fetch(request: Request, env) -> Response:
    """Handle incoming webhook from HCP Terraform."""

    # Only accept POST requests
    if request.method != "POST":
        return Response("Method not allowed", status=405)

    # Validate webhook URL is configured
    discord_webhook_url = getattr(env, 'DISCORD_WEBHOOK_URL', None)
    if not discord_webhook_url:
        print("DISCORD_WEBHOOK_URL secret is not configured")
        return Response("Server misconfiguration", status=500)

    # Get raw body for HMAC verification
    raw_body = await request.text()

    # Optional HMAC signature verification
    hmac_secret = getattr(env, 'HMAC_SECRET', None)
    if hmac_secret:
        signature = request.headers.get("X-TFE-Notification-Signature")
        if not signature:
            print("Missing X-TFE-Notification-Signature header")
            return Response("Missing signature", status=401)
        if not verify_hmac(raw_body, signature, hmac_secret):
            print("Invalid HMAC signature")
            return Response("Invalid signature", status=401)

    # Parse request body
    try:
        payload = json.loads(raw_body)
    except json.JSONDecodeError as e:
        print(f"Failed to parse request body: {e}")
        return Response("Invalid JSON payload", status=400)

    # Extract notification data
    notifications = payload.get("notifications", [])
    if not notifications:
        print(f"Missing notifications in payload: workspace={payload.get('workspace_name')}")
        return Response("No notification data", status=400)

    notification = notifications[0]

    # Color mapping for run status (Discord embed colors)
    colors = {
        "planned": 0x3498db,    # blue
        "applied": 0x2ecc71,    # green
        "errored": 0xe74c3c,    # red
        "canceled": 0x95a5a6,   # gray
        "planning": 0xf39c12,   # orange
        "applying": 0xf39c12,   # orange
        "discarded": 0x95a5a6,  # gray
    }

    status_emoji = {
        "planned": "📋",
        "applied": "✅",
        "errored": "❌",
        "canceled": "🚫",
        "planning": "🔄",
        "applying": "🔄",
        "discarded": "🗑️",
    }

    status = notification.get("run_status", "unknown")
    color = colors.get(status, 0x7289da)
    emoji = status_emoji.get(status, "❓")

    # Log unknown statuses
    if status not in colors:
        print(f"Unknown run status: {status}, run_id={notification.get('run_id')}")

    # Sanitize inputs for Discord embed
    safe_status = sanitize_for_discord(status)
    safe_workspace = sanitize_for_discord(payload.get("workspace_name")) or "unknown"
    safe_run_id = sanitize_for_discord(notification.get("run_id"))
    run_message = notification.get("run_message")
    safe_message = sanitize_for_discord(run_message) if run_message else None

    # Validate run URL
    run_url = notification.get("run_url")
    run_url = run_url if is_valid_terraform_url(run_url) else None

    # Build description lines
    description_lines = [
        f"**Workspace:** {safe_workspace}",
        f"**Run:** [{safe_run_id}]({run_url})" if run_url else f"**Run:** {safe_run_id}",
    ]
    if safe_message:
        description_lines.append(f"**Message:** {safe_message}")

    # Build Discord embed
    embed = {
        "embeds": [{
            "title": f"{emoji} Terraform {safe_status.capitalize()}",
            "description": "\n".join(description_lines),
            "color": color,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "footer": {"text": "HCP Terraform"},
        }]
    }

    # Send to Discord
    try:
        async with httpx.AsyncClient() as client:
            discord_response = await client.post(
                discord_webhook_url,
                json=embed,
                headers={"Content-Type": "application/json"},
            )
    except httpx.RequestError as e:
        print(f"Network error reaching Discord: {e}")
        return Response("Failed to reach Discord", status=503)

    if not discord_response.is_success:
        print(f"Discord API error: status={discord_response.status_code}")

        if discord_response.status_code == 429:
            retry_after = discord_response.headers.get("Retry-After", "60")
            return Response(
                "Discord rate limited",
                status=503,
                headers={"Retry-After": retry_after},
            )
        return Response(
            f"Discord webhook failed: {discord_response.status_code}",
            status=502,
        )

    return Response("OK", status=200)
