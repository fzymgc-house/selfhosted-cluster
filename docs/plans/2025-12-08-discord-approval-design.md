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
3. **Required:** Configure Cloudflare Access for authentication

**Security Rationale:**
Resume/cancel URLs must be protected by Cloudflare Access to prevent unauthorized approvals. While Windmill's URLs contain cryptographic signatures, adding Cloudflare Access provides defense-in-depth:
- Prevents URL leakage from Discord channel history
- Provides audit trail of who approved changes
- Adds additional layer against replay attacks

## API Verification

**Windmill Python SDK:** Confirmed `wmill.get_resume_urls()` exists
**Documentation:** https://docs.windmill.dev/docs/flows/flow_approval
**Returns:** Dictionary with `resume` and `cancel` keys containing signed URLs
**Parameters:** Optional approver string (not used in our implementation)

```python
import wmill

urls = wmill.get_resume_urls()
# Returns: {"resume": "http://...", "cancel": "http://..."}
```

## Architecture

### Modified Components

**1. `notify_approval.py`**
- Call `wmill.get_resume_urls()` to get internal resume/cancel URLs
- Transform internal URLs to public tunnel URLs using `urllib.parse`:
  - From: `http://windmill.windmill.svc.cluster.local/api/...`
  - To: `https://windmill.fzymgc.house/api/...`
- Change button style from `custom_id` (styles 3, 4) to Link buttons (style 5)
- Return `message_id` for downstream message editing
- Extract Discord limits to named constants

**2. `notify_status.py`**
- Add optional parameter: `approval_message_id`
- If provided, edit the original approval message via Discord PATCH API
- Remove buttons (Discord doesn't support disabling Link buttons)
- Update embed to show final status (success/failure)
- Still send new notification (existing behavior)

**3. `deploy_vault.flow/flow.yaml`**
- Pass `message_id` from notify-approval through flow
- Provide `message_id` to notify-success and notify-failure
- No changes needed for cancellation (Windmill handles cancel URL natively)

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
    - Flow resumes                        - Flow cancels immediately
    ↓                                     - Message left unchanged
6a. terraform_apply runs                  (user sees cancellation in
    ↓                                      Windmill UI)
7a. notify_success
    - Sends success notification
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

**Windmill Behavior (Verified from Documentation):**
- Windmill flows use DAG architecture where any step can access `results.{id}` from any previous step
- failure_module is a special step that runs on error, receiving `error.message` from failed step
- Based on general step architecture, failure_module SHOULD support `results["step-id"]` syntax
- **Note:** Current `deploy_vault` flow doesn't test this - verification needed during implementation
- **Fallback:** If results access not supported, send generic failure notification without message update

### Cancellation

**Scenario:** User clicks Reject button

**Handling:**
- Windmill cancel URL is called
- Flow cancels immediately
- No cleanup code runs (Windmill limitation)

**Windmill Behavior (Verified):**
- Cancel URL triggers immediate flow cancellation
- Windmill does NOT support cancellation handlers with context
- No mechanism to run cleanup code when cancel URL is called
- Flow simply terminates, similar to timeout behavior

**Implementation Approach:**
- **Option 1 (Recommended):** Accept that rejection leaves message unchanged
  - Simplest approach, avoids complexity
  - User can still see outcome in Windmill UI
  - Message remains visible as audit trail
- **Option 2:** Polling cleanup script
  - Separate scheduled flow checks for canceled runs
  - Updates Discord messages for canceled flows
  - Adds complexity, potential for missed updates
- **Option 3:** Don't offer Reject button
  - Only provide Approve + View Details buttons
  - Users can cancel via Windmill UI if needed
  - Simpler Discord UX, clear expectations

**Decision:** Use Option 1 for initial implementation. Rejection cancels flow, message remains unchanged. This is acceptable because the Windmill UI shows the cancellation status and the Discord message serves as an audit record.

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
import requests
from datetime import datetime
from typing import TypedDict
from urllib.parse import urlparse, urlunparse

# Discord API limits
DISCORD_EMBED_FIELD_LIMIT = 1000
DISCORD_EMBED_TITLE_LIMIT = 256

class discord_bot_configuration(TypedDict):
    application_id: str
    public_key: str

class c_discord_bot_token_configuration(TypedDict):
    token: str
    channel_id: str

def make_public_url(internal_url: str) -> str:
    """Transform internal Windmill URL to public tunnel URL."""
    parsed = urlparse(internal_url)
    return urlunparse((
        'https',  # scheme
        'windmill.fzymgc.house',  # netloc
        parsed.path,
        parsed.params,
        parsed.query,
        parsed.fragment
    ))

def main(discord: discord_bot_configuration, discord_bot_token: c_discord_bot_token_configuration, module: str, plan_summary: str, plan_details: str, run_id: str):
    # Get internal resume URLs from Windmill SDK
    urls = wmill.get_resume_urls()

    # Transform to public URLs
    public_resume = make_public_url(urls['resume'])
    public_cancel = make_public_url(urls['cancel'])

    # Truncate plan details to fit Discord limits
    truncated_details = (
        plan_details[:DISCORD_EMBED_FIELD_LIMIT] + "..."
        if len(plan_details) > DISCORD_EMBED_FIELD_LIMIT
        else plan_details
    )

    payload = {
        "embeds": [{
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
        }],
        "components": [{
            "type": 1,  # Action Row
            "components": [
                {
                    "type": 2,  # Button
                    "style": 5,  # Link
                    "label": "✅ Approve",
                    "url": public_resume
                },
                {
                    "type": 2,  # Button
                    "style": 5,  # Link
                    "label": "❌ Reject",
                    "url": public_cancel
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
        f"https://discord.com/api/v10/channels/{discord_bot_token['channel_id']}/messages",
        headers={"Authorization": f"Bot {discord_bot_token['token']}", "Content-Type": "application/json"},
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
   - Verify flow cancels in Windmill UI
   - Verify message remains unchanged (expected behavior)

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

## Rollback Strategy

If Discord approval buttons don't work as expected after implementation:

### Quick Rollback (Revert Changes)

**When to use:** Critical failure, buttons completely broken

**Steps:**
1. Revert `notify_approval.py` to previous version (restore `custom_id` buttons)
2. Revert `notify_status.py` to previous version (no message editing)
3. Revert `deploy_vault.flow/flow.yaml` to previous version
4. Deploy via `wmill sync push`
5. Verify flows run with non-functional buttons (approval via Windmill UI only)

**Verification:**
```bash
# Check git history for last working version
git log --oneline windmill/f/terraform/notify_approval.py

# Revert to specific commit
git checkout <commit-hash> windmill/f/terraform/notify_approval.py
git checkout <commit-hash> windmill/f/terraform/notify_status.py
git checkout <commit-hash> windmill/f/terraform/deploy_vault.flow/flow.yaml

# Push to Windmill
cd windmill
wmill sync push
```

**Impact:** Back to original behavior - buttons don't work, approvals via Windmill UI

### Partial Rollback (Keep Some Features)

**When to use:** Message editing works, but buttons don't

**Options:**
1. **Remove buttons entirely** - Send notification without buttons, approval via Windmill UI
2. **Keep "View Details" button only** - Remove Approve/Reject, keep link to Windmill UI
3. **Revert to custom_id buttons** - Non-functional but familiar UX

### Testing Rollback

Add to Phase 1 testing checklist:
- [ ] Document current working state before changes
- [ ] Test rollback procedure in staging workspace first
- [ ] Verify reverted flow can still run end-to-end
- [ ] Confirm no data loss or stuck flows

### Prevention

**Pre-deployment:**
- Test thoroughly in Windmill staging workspace
- Verify Cloudflare Tunnel accessible before deploying button changes
- Create git tag before merging to main: `git tag windmill-approval-v1-pre-link-buttons`

**Monitoring:**
- Check flow success rate after deployment
- Monitor for stuck flows (suspended > 24 hours)
- Watch Discord for error reports

## Rollout

1. Complete #215 (Cloudflare Tunnel with Cloudflare Access)
2. Update `notify_approval.py` (Link buttons with public URLs)
3. Update `notify_status.py` (add message editing)
4. Update `deploy_vault.flow/flow.yaml` (pass message_id to notify-success/failure)
5. Test phases 1-3 (component, integration, edge cases)
6. Document pattern for reuse

## Reusability Pattern

### Shared Library Structure

To apply this approval pattern to other flows (`deploy_grafana`, `deploy_authentik`), extract common functionality:

**File:** `windmill/f/terraform/lib/discord_approval.py`

```python
"""Shared Discord approval helper functions."""

from datetime import datetime
from typing import TypedDict
from urllib.parse import urlparse, urlunparse

import requests
import wmill

# Discord API limits
DISCORD_EMBED_FIELD_LIMIT = 1000
DISCORD_EMBED_TITLE_LIMIT = 256


class DiscordBotConfig(TypedDict):
    """Discord bot configuration resource type."""
    application_id: str
    public_key: str


class DiscordBotToken(TypedDict):
    """Discord bot token and channel configuration resource type."""
    token: str
    channel_id: str


def make_public_url(internal_url: str, public_domain: str = "windmill.fzymgc.house") -> str:
    """
    Transform internal Windmill URL to public tunnel URL.

    Args:
        internal_url: Internal URL from Windmill (e.g., http://windmill.windmill.svc...)
        public_domain: Public domain for Cloudflare Tunnel

    Returns:
        Public HTTPS URL accessible from Discord
    """
    parsed = urlparse(internal_url)
    return urlunparse((
        'https',
        public_domain,
        parsed.path,
        parsed.params,
        parsed.query,
        parsed.fragment
    ))


def send_approval_notification(
    discord_bot_token: DiscordBotToken,
    title: str,
    module: str,
    plan_summary: str,
    plan_details: str,
    run_id: str
) -> dict:
    """
    Send approval request to Discord with Link buttons.

    Args:
        discord_bot_token: Discord bot token and channel configuration
        title: Notification title
        module: Module name being deployed
        plan_summary: Short summary of changes
        plan_details: Full change details
        run_id: Windmill run ID

    Returns:
        dict with message_id and notified status
    """
    # Get resume URLs from Windmill
    urls = wmill.get_resume_urls()

    # Transform to public URLs
    public_resume = make_public_url(urls['resume'])
    public_cancel = make_public_url(urls['cancel'])

    # Truncate to Discord limits
    truncated_details = (
        plan_details[:DISCORD_EMBED_FIELD_LIMIT] + "..."
        if len(plan_details) > DISCORD_EMBED_FIELD_LIMIT
        else plan_details
    )

    payload = {
        "embeds": [{
            "title": title,
            "description": f"Module: **{module}**",
            "color": 0xFFA500,  # Orange
            "fields": [
                {"name": "Plan Summary", "value": f"```\n{plan_summary}\n```", "inline": False},
                {"name": "Plan Details", "value": f"```terraform\n{truncated_details}\n```", "inline": False},
                {"name": "Run ID", "value": run_id, "inline": True},
            ],
            "timestamp": datetime.utcnow().isoformat(),
            "footer": {"text": "Windmill Terraform GitOps"},
        }],
        "components": [{
            "type": 1,  # Action Row
            "components": [
                {
                    "type": 2,  # Button
                    "style": 5,  # Link
                    "label": "✅ Approve",
                    "url": public_resume
                },
                {
                    "type": 2,  # Button
                    "style": 5,  # Link
                    "label": "❌ Reject",
                    "url": public_cancel
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
        f"https://discord.com/api/v10/channels/{discord_bot_token['channel_id']}/messages",
        headers={"Authorization": f"Bot {discord_bot_token['token']}", "Content-Type": "application/json"},
        json=payload
    )

    if not response.ok:
        raise Exception(f"Discord API failed: {response.status_code} - {response.text}")

    message = response.json()
    return {"message_id": message["id"], "notified": True}


def update_approval_message(
    discord_bot_token: DiscordBotToken,
    message_id: str,
    title: str,
    status: str,
    details: str,
    color: int
) -> None:
    """
    Update original approval message with final status.

    Args:
        discord_bot_token: Discord bot token and channel configuration
        message_id: Original message ID to update
        title: New message title
        status: Status message
        details: Status details
        color: Discord embed color (0x00FF00 for success, 0xFF0000 for failure)
    """
    try:
        edit_payload = {
            "embeds": [{
                "title": title,
                "color": color,
                "fields": [
                    {"name": "Status", "value": status, "inline": False},
                    {"name": "Details", "value": details, "inline": False},
                ],
                "timestamp": datetime.utcnow().isoformat(),
            }],
            "components": []  # Remove buttons
        }

        response = requests.patch(
            f"https://discord.com/api/v10/channels/{discord_bot_token['channel_id']}/messages/{message_id}",
            headers={"Authorization": f"Bot {discord_bot_token['token']}", "Content-Type": "application/json"},
            json=edit_payload
        )

        if not response.ok and response.status_code != 404:
            # Ignore 404 (message deleted), raise other errors
            raise Exception(f"Discord API failed: {response.status_code} - {response.text}")
    except requests.HTTPError as e:
        if e.response.status_code != 404:
            raise
```

### Using the Shared Library

**In `notify_approval.py`:**
```python
import sys
sys.path.append('./f/terraform/lib')
from discord_approval import send_approval_notification

def main(discord_bot_token, module, plan_summary, plan_details, run_id):
    return send_approval_notification(
        discord_bot_token=discord_bot_token,
        title="🚨 Terraform Apply Approval Required",
        module=module,
        plan_summary=plan_summary,
        plan_details=plan_details,
        run_id=run_id
    )
```

**In `notify_status.py`:**
```python
import sys
sys.path.append('./f/terraform/lib')
from discord_approval import update_approval_message

def main(discord_bot_token, module, status, details, approval_message_id=None):
    # Send new notification (existing logic)
    send_new_notification(...)

    # Update approval message if provided
    if approval_message_id:
        color = 0x00FF00 if status == "success" else 0xFF0000
        title = "✅ Terraform Apply Successful" if status == "success" else "⚠️ Terraform Apply Failed"
        update_approval_message(
            discord_bot_token=discord_bot_token,
            message_id=approval_message_id,
            title=title,
            status=status,
            details=details,
            color=color
        )
```

### Benefits

1. **Single Source of Truth**: URL transformation, Discord limits, error handling in one place
2. **Consistent UX**: All Terraform flows use same button layout and styling
3. **Easy Updates**: Change button behavior once, applies to all flows
4. **Type Safety**: Shared TypedDicts ensure consistent resource structures
5. **Testability**: Library functions can be unit tested independently

### Migration Path

1. **Phase 1**: Implement inline in `deploy_vault` flow (validate approach)
2. **Phase 2**: Extract to shared library after validation
3. **Phase 3**: Migrate `deploy_grafana` and `deploy_authentik` to use library
4. **Phase 4**: Add library functions for other notification types (warnings, info)

## Future Work

- Apply pattern to `deploy_grafana` and `deploy_authentik` flows
- Consider adding approval timeout warnings
- Add metrics/monitoring for approval response times
- Investigate richer Discord interactions (slash commands)
- Extract shared library after deploy_vault validation
