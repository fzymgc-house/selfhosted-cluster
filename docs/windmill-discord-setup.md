# Windmill Discord Notifications Setup

Guide for configuring Discord webhooks for Windmill approval notifications.

## Overview

Discord webhooks will be used to notify when Terraform apply operations require approval in Windmill flows.

## Setup Steps

### 1. Create Discord Webhook

1. Open Discord and navigate to your server
2. Go to Server Settings → Integrations → Webhooks
3. Click "New Webhook"
4. Configure:
   - **Name**: Windmill Terraform Approvals
   - **Channel**: Select appropriate channel (e.g., #infrastructure-alerts)
   - **Avatar**: Optional - upload Windmill logo
5. Click "Copy Webhook URL"

### 2. Store Webhook in Vault

Store the Discord webhook URL in Vault:

```bash
vault kv put secret/fzymgc-house/cluster/windmill \
  discord_webhook_url="https://discord.com/api/webhooks/..."
```

### 3. Create Discord Resource in Windmill

After workspace creation:

1. Login to Windmill at https://windmill.fzymgc.house
2. Navigate to `terraform-gitops` workspace
3. Go to **Resources** → **Add a resource**
4. Create a custom resource type for Discord:

```json
{
  "webhook_url": "<from-vault>",
  "username": "Windmill Terraform",
  "avatar_url": "https://www.windmill.dev/img/logo.svg"
}
```

5. Save as: `u/admin/discord_notifications`

## Usage in Flows

### Approval Notification Script

Create a Windmill script to send Discord notifications:

**Path**: `terraform/notify-approval`

```typescript
import * as wmill from "windmill-client"

type DiscordResource = {
  webhook_url: string
  username?: string
  avatar_url?: string
}

export async function main(
  discord: DiscordResource,
  module: string,
  planSummary: string,
  approvalUrl: string
) {
  const payload = {
    username: discord.username || "Windmill Terraform",
    avatar_url: discord.avatar_url,
    embeds: [{
      title: `\ud83d\udea8 Terraform Apply Approval Required`,
      description: `Module: **${module}**`,
      color: 0xFFA500, // Orange
      fields: [
        {
          name: "Plan Summary",
          value: `\`\`\`\n${planSummary}\n\`\`\``,
          inline: false
        },
        {
          name: "Approval Required",
          value: `[Click here to review and approve](${approvalUrl})`,
          inline: false
        }
      ],
      timestamp: new Date().toISOString(),
      footer: {
        text: "Windmill Terraform GitOps"
      }
    }]
  }

  const response = await fetch(discord.webhook_url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  })

  if (!response.ok) {
    throw new Error(`Discord webhook failed: ${response.statusText}`)
  }

  return { notified: true }
}
```

### Flow Integration

Use in Terraform deployment flow:

```yaml
# After terraform plan step
- id: notify-approval
  type: script
  path: terraform/notify-approval
  args:
    discord:
      $res: u/admin/discord_notifications
    module: ${flow.module}
    planSummary: ${result.terraform-plan.summary}
    approvalUrl: ${flow.approval_url}

# Approval step
- id: approval
  type: approval
  timeout: 86400  # 24 hours
  approvers:
    - u/admin

# Notify approval decision
- id: notify-result
  type: script
  path: terraform/notify-result
  args:
    discord:
      $res: u/admin/discord_notifications
    module: ${flow.module}
    approved: ${result.approval.approved}
```

## Message Templates

### Approval Required

```
🚨 Terraform Apply Approval Required

Module: **tf/vault**

Plan Summary:
```
Plan: 3 to add, 2 to change, 1 to destroy
```

[Click here to review and approve](https://windmill.fzymgc.house/runs/abc123)
```

### Approval Granted

```
✅ Terraform Apply Approved

Module: **tf/vault**
Approved by: @admin
Status: Applying changes...
```

### Apply Complete

```
✅ Terraform Apply Complete

Module: **tf/vault**
Duration: 45 seconds
Changes: 3 added, 2 changed, 1 destroyed

[View run details](https://windmill.fzymgc.house/runs/abc123)
```

### Apply Failed

```
❌ Terraform Apply Failed

Module: **tf/vault**
Error: Failed to apply changes

[View error details](https://windmill.fzymgc.house/runs/abc123)
```

## Testing

Test the Discord integration:

1. Create test script in Windmill
2. Use Discord resource to send test message
3. Verify message appears in Discord channel
4. Check formatting and links

```typescript
// Test script
export async function main() {
  const discord = wmill.getResource("u/admin/discord_notifications")

  await fetch(discord.webhook_url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      content: "✅ Discord webhook test successful!"
    })
  })
}
```

## Vault Configuration

Complete Vault secret structure:

```bash
vault kv put secret/fzymgc-house/cluster/windmill \
  admin_password="<existing>" \
  oidc_client_id="<existing>" \
  oidc_client_secret="<existing>" \
  terraform_gitops_token="<from-#128>" \
  s3_access_key="<from-#130>" \
  s3_secret_key="<from-#130>" \
  s3_bucket="windmill-storage" \
  s3_endpoint="https://gateway.storjshare.io" \
  discord_webhook_url="https://discord.com/api/webhooks/..."
```

## Security Considerations

- **Webhook URL**: Treat as sensitive - grants posting access to Discord channel
- **Channel Selection**: Use dedicated infrastructure channel, not general chat
- **Rate Limiting**: Discord webhooks have rate limits (30 requests/minute)
- **Message Size**: Discord embeds limited to 6000 characters total

## Troubleshooting

### Webhook Not Working

```bash
# Test webhook directly
curl -X POST "https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content": "Test message"}'
```

### Messages Not Appearing

- Check webhook URL is correct
- Verify channel permissions
- Check Discord server status
- Review Windmill worker logs for errors

## References

- Discord Webhooks Documentation: https://discord.com/developers/docs/resources/webhook
- Discord Embed Limits: https://discord.com/developers/docs/resources/message#embed-limits
