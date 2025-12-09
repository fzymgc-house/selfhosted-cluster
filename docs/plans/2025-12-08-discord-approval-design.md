# Discord Approval Flow Design

**Date:** 2025-12-08
**Status:** Proposed
**Blocks:** Issue #237 (Discord approval testing), Issue #238 (End-to-end Terraform testing)
**Dependencies:** Issue #215 (Cloudflare Tunnel for Windmill)

## Problem

The Discord approval buttons in Windmill Terraform flows don't work. They use `custom_id` which requires a Discord interactions endpoint that doesn't exist. Users cannot approve Terraform changes from Discord - they must use the Windmill UI instead.

## Solution

Replace `custom_id` buttons with Link buttons that use Windmill's built-in resume/cancel URLs. Expose these URLs via Cloudflare Tunnel (#215) so Discord can reach them.

## Dependencies

**Must complete first:**
1. Issue #215 - Deploy Cloudflare Tunnel for Windmill
2. Configure tunnel to expose `/api/w/*/jobs/resume/*` endpoints
3. (Optional) Configure Cloudflare Access for authentication

## Architecture

### Modified Components

**1. `notify_approval.py`**
- Call `wmill.get_resume_urls()` to get internal resume/cancel URLs
- Transform internal URLs to public tunnel URLs:
  - From: `http://windmill.windmill.svc.cluster.local/api/...`
  - To: `https://windmill.fzymgc.house/api/...`
- Change button style from `custom_id` (styles 3, 4) to Link buttons (style 5)
- Return `message_id` for downstream message editing

**2. `notify_status.py`**
- Add optional parameter: `approval_message_id`
- If provided, edit the original approval message via Discord PATCH API
- Remove buttons (Discord doesn't support disabling Link buttons)
- Update embed to show final status (success/failure)
- Still send new notification (existing behavior)

**3. New: `handle_rejection.py`**
- Runs when user clicks Reject (cancel URL)
- Sends rejection notification to Discord
- Edits original approval message to show rejection status

**4. `deploy_vault.flow/flow.yaml`**
- Pass `message_id` from notify-approval through flow
- Provide `message_id` to notify-success and notify-failure
- Add cancellation handler that calls `handle_rejection.py`

## Data Flow

```
1. Terraform plan completes
   ↓
2. notify_approval.py
   - Gets wmill.get_resume_urls()
   - Transforms to public URLs
   - Creates Discord message with Link buttons
   - Returns {message_id, notified}
   ↓
3. Flow suspends (approval step)
   ↓
4. User clicks button in Discord
   ↓
5a. Approve clicked                   5b. Reject clicked
    - Discord → Tunnel                    - Discord → Tunnel
    - Tunnel → Windmill resume            - Tunnel → Windmill cancel
    - Flow resumes                        - Flow cancels
    ↓                                     ↓
6a. terraform_apply runs              6b. handle_rejection.py
    ↓                                     - Sends rejection notification
7a. notify_success                        - Edits approval message
    - Sends success notification          - Shows "❌ Rejected"
    - Edits approval message
    - Shows "✅ Approved & Applied"

7b. (On failure) notify_failure
    - Sends failure notification
    - Edits approval message
    - Shows "⚠️ Approved but Failed"
```

## Error Handling

### Apply Failure After Approval

**Scenario:** User approves, Terraform apply fails

**Handling:**
- Failure module runs with `approval_message_id`
- Sends NEW failure notification (existing behavior)
- Edits original approval message:
  - Title: "⚠️ Terraform Apply Failed"
  - Status: "Approved but apply failed"
  - Removes buttons
  - Adds error details

### Cancellation

**Scenario:** User clicks Reject button

**Handling:**
- Windmill calls cancel endpoint
- Flow cancels, triggers cancellation handler
- `handle_rejection.py` runs:
  - Sends rejection notification
  - Edits approval message to show rejection
  - Removes buttons

**Challenge:** Verify Windmill supports passing context (message_id) to cancellation handlers.

**Fallback:** If cancellation context not supported, rejection cancels flow silently. Original message remains unchanged (not ideal, but functional).

### Multiple Approval Clicks

**Scenario:** Multiple users click Approve

**Handling:**
- Windmill resume URLs are single-use tokens
- First click resumes flow
- Subsequent clicks return error
- No code changes needed - Windmill handles this natively

### Network Failure

**Scenario:** Tunnel down when user clicks button

**Handling:**
- Discord shows "Failed to load URL" error
- Flow remains suspended
- User can retry when tunnel recovers
- Consider: Add monitoring/alerting for tunnel health

### Message Deletion

**Scenario:** User deletes Discord message before flow completes

**Handling:**
```python
# In notify_status.py
try:
    requests.patch(...)  # Edit approval message
except requests.HTTPError as e:
    if e.response.status_code == 404:
        # Message deleted, ignore
        pass
    else:
        raise
```
- Catch 404 errors from Discord API
- Still send new notification (that succeeds)

## Implementation

### Code Changes

**`notify_approval.py`:**
```python
import wmill

def main(discord, discord_bot_token, module, plan_summary, plan_details, run_id):
    # Get internal resume URLs
    urls = wmill.get_resume_urls("discord-approval")

    # Transform to public URLs
    public_resume = urls['resume'].replace(
        'http://windmill.windmill.svc.cluster.local',
        'https://windmill.fzymgc.house'
    )
    public_cancel = urls['cancel'].replace(
        'http://windmill.windmill.svc.cluster.local',
        'https://windmill.fzymgc.house'
    )

    # Create Link buttons (style: 5)
    components = [{
        "type": 1,
        "components": [
            {
                "type": 2,
                "style": 5,  # Link
                "label": "✅ Approve",
                "url": public_resume
            },
            {
                "type": 2,
                "style": 5,  # Link
                "label": "❌ Reject",
                "url": public_cancel
            },
            {
                "type": 2,
                "style": 5,
                "label": "View Details",
                "url": f"https://windmill.fzymgc.house/runs/{run_id}"
            }
        ]
    }]

    # Send to Discord
    response = requests.post(...)
    message = response.json()

    return {
        "message_id": message["id"],
        "notified": True
    }
```

**`notify_status.py`:**
```python
def main(discord_bot_token, module, status, details, approval_message_id=None):
    # Send new notification (existing)
    send_notification(...)

    # Edit original approval message if provided
    if approval_message_id:
        try:
            edit_payload = {
                "embeds": [...],  # Updated with status
                "components": []  # Remove buttons
            }
            requests.patch(
                f"https://discord.com/api/v10/channels/{channel_id}/messages/{approval_message_id}",
                headers={"Authorization": f"Bot {token}"},
                json=edit_payload
            )
        except requests.HTTPError as e:
            if e.response.status_code != 404:
                raise
```

**`handle_rejection.py`:**
```python
def main(discord_bot_token, module, approval_message_id):
    # Send rejection notification
    send_rejection_notification(...)

    # Edit approval message
    edit_payload = {
        "embeds": [{
            "title": "❌ Terraform Apply Rejected",
            "description": f"Module: **{module}**",
            "color": 0xFF0000,
            "fields": [{
                "name": "Status",
                "value": "Rejected by user"
            }]
        }],
        "components": []
    }
    requests.patch(...)
```

### Flow Changes

**`deploy_vault.flow/flow.yaml`:**
```yaml
- id: notify-approval
  value:
    type: script
    path: f/terraform/notify_approval
    # Returns {message_id, notified}

- id: approval
  value:
    type: identity
    suspend:
      required_events: 1
      timeout: 86400

- id: terraform-apply
  value:
    type: script
    path: f/terraform/terraform_apply

- id: notify-success
  value:
    type: script
    path: f/terraform/notify_status
    input_transforms:
      approval_message_id:
        type: javascript
        expr: 'results["notify-approval"].message_id'
      # ... other inputs

failure_module:
  id: notify-failure
  value:
    type: script
    path: f/terraform/notify_status
    input_transforms:
      approval_message_id:
        type: javascript
        expr: 'results["notify-approval"].message_id'
      # ... other inputs
```

## Testing

### Phase 1: Component Testing (Pre-Tunnel)

Test individual components before Cloudflare Tunnel is deployed:

1. **notify_approval.py:**
   - Run manually in Windmill UI
   - Verify calls `wmill.get_resume_urls()`
   - Verify URL transformation
   - Verify Discord message sent with Link buttons
   - Buttons won't work yet (no tunnel)

2. **notify_status.py:**
   - Create test Discord message
   - Run manually with `approval_message_id`
   - Verify original message edited
   - Verify buttons removed

3. **handle_rejection.py:**
   - Create test approval message
   - Run manually
   - Verify rejection notification sent
   - Verify original message updated

### Phase 2: Integration Testing (Post-Tunnel)

After Cloudflare Tunnel deployed:

1. **Minimal flow test:**
   - Create simple flow that just suspends
   - Send approval notification
   - Click Approve in Discord
   - Verify flow resumes
   - Verify message updated

2. **Rejection test:**
   - Trigger flow
   - Click Reject in Discord
   - Verify flow cancels
   - Verify rejection notification
   - Verify message updated

3. **Terraform test (Issue #238):**
   - Make safe Terraform change (e.g., Vault policy description)
   - Trigger `deploy_vault` flow
   - Click Approve in Discord
   - Verify Terraform apply runs
   - Verify change applied to Vault
   - Verify success notification + message update

### Phase 3: Edge Cases

1. **Apply failure:**
   - Make invalid Terraform change
   - Approve in Discord
   - Verify failure notification + message update

2. **Double-click:**
   - Click Approve
   - Click Approve again immediately
   - Verify second click shows error
   - Verify flow runs once

3. **Message deletion:**
   - Trigger flow
   - Delete approval message
   - Approve via Windmill UI
   - Verify no crash, notification sent

## Test Checklist (Issue #237)

- [ ] Discord notification sent with Link buttons
- [ ] Approve button resumes flow
- [ ] Reject button cancels flow
- [ ] Success updates approval message
- [ ] Failure updates approval message
- [ ] Rejection sends notification
- [ ] End-to-end with real Terraform change

## Rollout

1. Complete #215 (Cloudflare Tunnel)
2. Update `notify_approval.py`
3. Update `notify_status.py`
4. Create `handle_rejection.py`
5. Update `deploy_vault.flow/flow.yaml`
6. Test phases 1-3
7. Document pattern for reuse

## Future Work

- Apply pattern to `deploy_grafana` and `deploy_authentik` flows
- Consider adding approval timeout warnings
- Add metrics/monitoring for approval response times
- Investigate richer Discord interactions (slash commands)
