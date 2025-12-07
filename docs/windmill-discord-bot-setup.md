# Windmill Discord Bot Setup

Guide for configuring a Discord bot for Windmill approval notifications and interactions.

## Overview

A Discord bot provides richer integration than simple webhooks:
- **Interactive buttons** for approvals directly in Discord
- **Two-way communication** with Windmill
- **Proper authentication** via bot tokens
- **Future extensibility** - slash commands, custom interactions

This is the recommended approach over webhooks.

## Prerequisites

- Discord server with admin access
- Vault CLI configured and authenticated
- Windmill workspace created (#128)

## Setup Steps

### 1. Create Discord Bot Application

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Click **"New Application"**
3. Configure:
   - **Name**: `Windmill Terraform Bot`
   - **Description**: `Terraform approval notifications and interactions`
4. Click **"Create"**

### 2. Configure Bot

1. Navigate to **Bot** section in left sidebar
2. Click **"Add Bot"** → **"Yes, do it!"**
3. Configure bot settings:
   - ❌ **Public Bot**: Disabled (unchecked)
   - ❌ **Requires OAuth2 Code Grant**: Disabled (unchecked)
   - ❌ **Presence Intent**: Disabled
   - ❌ **Server Members Intent**: Disabled
   - ✅ **Message Content Intent**: **Enabled (checked)**
4. Under **"Token"**, click **"Reset Token"** and copy it
   - Format: `MTxxxxx.xxxxxx.xxxxxxxxxxxxxxxxxxxxxxxxxxx`
   - **Save this** - you'll need it for Vault

### 3. Collect Bot Credentials

You need these 4 values:

| Credential | Where to Find |
|------------|---------------|
| **Bot Token** | Bot → Token section (from step 2) |
| **Application ID** | General Information → Application ID |
| **Public Key** | General Information → Public Key |
| **Channel ID** | See instructions below |

**To get Channel ID:**
1. In Discord: User Settings → Advanced → Enable **Developer Mode**
2. Right-click your target channel → **Copy ID**
3. Save this channel ID

### 4. Add Bot to Server

1. Navigate to **OAuth2** → **URL Generator**
2. Select **Scopes**:
   - ✅ `bot`
   - ✅ `applications.commands`
3. Select **Bot Permissions**:
   - ✅ `Send Messages`
   - ✅ `Send Messages in Threads`
   - ✅ `Embed Links`
   - ✅ `Attach Files`
4. Copy the generated URL at bottom
5. Open URL in browser
6. Select your Discord server
7. Click **"Authorize"**

### 5. Store Credentials in Vault

```bash
# Store all 4 bot credentials
vault kv put secret/fzymgc-house/cluster/windmill \
  discord_bot_token="MTxxxxx.xxxxxx.xxxxxxxxxxxxxxxxxxxxxxxxxxx" \
  discord_application_id="1234567890123456789" \
  discord_public_key="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" \
  discord_channel_id="1234567890123456789"
```

**Verify stored:**
```bash
vault kv get secret/fzymgc-house/cluster/windmill
```

### 6. Create Discord Bot Resource in Windmill

After workspace creation (#128):

1. Login to Windmill: https://windmill.fzymgc.house
2. Navigate to `terraform-gitops` workspace
3. Go to **Resources** → **"Add a resource"**
4. Select type: **`discord_bot_configuration`**
5. Fill in values from Vault:

```json
{
  "bot_token": "<from vault: discord_bot_token>",
  "application_id": "<from vault: discord_application_id>",
  "public_key": "<from vault: discord_public_key>",
  "channel_id": "<from vault: discord_channel_id>"
}
```

6. **Path**: `u/admin/terraform_discord_bot`
7. Click **"Save"**

## Usage in Windmill Flows

### Send Approval Notification with Buttons

**Script Path**: `terraform/notify-approval`

```python
import requests
from datetime import datetime

def main(
    discord: dict,
    module: str,
    plan_summary: str,
    run_id: str
):
    """Send approval notification with interactive buttons to Discord."""

    # Create message with interactive buttons
    payload = {
        "embeds": [{
            "title": "🚨 Terraform Apply Approval Required",
            "description": f"Module: **{module}**",
            "color": 0xFFA500,  # Orange
            "fields": [
                {
                    "name": "Plan Summary",
                    "value": f"```\n{plan_summary[:1000]}\n```",
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
```

### Send Status Update (No Buttons)

**Script Path**: `terraform/notify-status`

```python
import requests
from datetime import datetime

def main(
    discord: dict,
    module: str,
    status: str,  # "success" or "failed"
    details: str
):
    """Send status notification to Discord."""

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

    payload = {
        "embeds": [{
            "title": status_config["title"],
            "description": f"Module: **{module}**",
            "color": status_config["color"],
            "fields": [{
                "name": "Details",
                "value": details[:1000],
                "inline": False
            }],
            "timestamp": datetime.utcnow().isoformat()
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
```

## Example Flow Integration

```yaml
summary: Terraform deployment with Discord notifications

# Run terraform plan
- id: terraform-plan
  type: script
  path: terraform/plan
  args:
    module: ${flow.module}

# Send approval request to Discord
- id: notify-approval
  type: script
  path: terraform/notify-approval
  args:
    discord:
      $res: u/admin/terraform_discord_bot
    module: ${flow.module}
    planSummary: ${result.terraform-plan.summary}
    runId: ${flow.id}

# Wait for manual approval
- id: approval
  type: approval
  timeout: 86400  # 24 hours
  approvers:
    - u/admin

# Apply changes
- id: terraform-apply
  type: script
  path: terraform/apply
  args:
    module: ${flow.module}

# Notify success
- id: notify-success
  type: script
  path: terraform/notify-status
  args:
    discord:
      $res: u/admin/terraform_discord_bot
    module: ${flow.module}
    status: success
    details: "Applied successfully"

# Error handler
error:
  - id: notify-failure
    type: script
    path: terraform/notify-status
    args:
      discord:
        $res: u/admin/terraform_discord_bot
      module: ${flow.module}
      status: failed
      details: ${error.message}
```

## Message Examples

### Approval Required
```
🚨 Terraform Apply Approval Required

Module: tf/vault

Plan Summary:
```
Plan: 3 to add, 2 to change, 1 to destroy
```

Run ID: abc-123-def

[✅ Approve] [❌ Reject] [View Details →]
```

### Success
```
✅ Terraform Apply Complete

Module: tf/vault

Details: Applied successfully in 45 seconds
```

### Failure
```
❌ Terraform Apply Failed

Module: tf/vault

Details: Error: Failed to create vault_policy.terraform
```

## Testing

Test the bot integration:

```python
import requests
import wmill

def main():
    """Test Discord bot connection."""
    discord = wmill.get_resource("u/admin/terraform_discord_bot")

    response = requests.post(
        f"https://discord.com/api/v10/channels/{discord['channel_id']}/messages",
        headers={
            "Authorization": f"Bot {discord['bot_token']}",
            "Content-Type": "application/json"
        },
        json={
            "content": "✅ Discord bot test successful!"
        }
    )

    return {
        "success": response.ok,
        "status_code": response.status_code
    }
```

## Complete Vault Configuration

All Windmill secrets in one place:

```bash
vault kv put secret/fzymgc-house/cluster/windmill \
  admin_password="<existing>" \
  oidc_client_id="<existing>" \
  oidc_client_secret="<existing>" \
  terraform_gitops_token="<from #128>" \
  s3_access_key="<from #130>" \
  s3_secret_key="<from #130>" \
  s3_bucket="windmill-storage" \
  s3_endpoint="https://gateway.storjshare.io" \
  discord_bot_token="MTxxxxx..." \
  discord_application_id="1234567890" \
  discord_public_key="xxxx..." \
  discord_channel_id="1234567890"
```

## Troubleshooting

### Bot Not Sending Messages

```bash
# Verify bot token is valid
vault kv get -field=discord_bot_token secret/fzymgc-house/cluster/windmill

# Test token manually
curl -H "Authorization: Bot <token>" \
  https://discord.com/api/v10/users/@me
```

**Common issues:**
- Channel ID incorrect
- Bot doesn't have "Send Messages" permission in channel
- Bot not added to server
- Bot token expired

### Button Interactions (Advanced)

Interactive buttons require setting up Discord's Interactions Endpoint URL.

This is **optional** - buttons can be cosmetic (Windmill UI approval still works).

For full interactivity:
1. Create Windmill webhook flow
2. Set as Discord Interactions Endpoint
3. Implement signature verification

See: https://www.windmill.dev/blog/knowledge-base-discord-bot

### Permission Issues

```bash
# Check bot is in Discord server
# Discord → Server Settings → Integrations
# Your bot should be listed

# Verify bot has access to channel
# Channel Settings → Permissions → Check bot role
```

## Security

- **Bot Token**: Treat like a password - never commit to Git
- **Public Key**: Required for interaction signature verification
- **Channel ID**: Restricts bot to specific channel
- **Scopes**: Only grant minimum required permissions

## References

- Discord Bot Guide: https://discord.com/developers/docs/topics/oauth2#bots
- Discord API: https://discord.com/developers/docs/reference
- Windmill Discord Tutorial: https://www.windmill.dev/blog/knowledge-base-discord-bot
- Resource Type: https://hub.windmill.dev/resource_types/104/discord_bot_configuration
