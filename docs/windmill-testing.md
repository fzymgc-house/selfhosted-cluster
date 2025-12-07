# Windmill Configuration Testing

Guide for testing and validating Windmill configuration before proceeding to production use.

## Prerequisites

Before running tests:

1. **Workspace variables configured** - Run `scripts/sync-vault-to-windmill-vars.sh`
2. **S3 credentials in Vault** (optional - can skip S3 tests if not configured)
3. **Discord bot configured** with messages permission in target channel
4. **GitHub token configured** with repo access

## Test Script

**Script Path**: `f/terraform/test_configuration`

This script validates all three integrations:
- Discord bot (send test message)
- GitHub token (access repository)
- S3 storage (write test file)

### Running the Test

1. Navigate to Windmill: https://windmill.fzymgc.house
2. Go to workspace: `terraform-gitops`
3. Find script: `f/terraform/test_configuration`
4. Click **"Run"**
5. Provide resource parameters:
   - `discord`: Select `u/admin/terraform_discord_bot`
   - `github`: Select `u/admin/github_token`
   - `s3`: Select `u/admin/terraform_s3_storage`
6. Click **"Run"**

### Expected Output

```json
{
  "overall_success": true,
  "results": {
    "discord": {
      "tested": true,
      "success": true,
      "error": null
    },
    "github": {
      "tested": true,
      "success": true,
      "error": null
    },
    "s3": {
      "tested": true,
      "success": true,
      "error": null
    }
  },
  "summary": "Discord: ✅, GitHub: ✅, S3: ✅"
}
```

### Discord Verification

If Discord test passes, you should see a message in your configured Discord channel:

```
✅ Windmill Configuration Test

Discord bot integration is working correctly!
```

### Common Issues

#### Discord Test Fails

**Error**: `HTTP 403: Missing Permissions`
- **Fix**: Ensure bot has "Send Messages" permission in the channel
- Check: Discord Server Settings → Integrations → Bot → Channel Permissions

**Error**: `HTTP 404: Unknown Channel`
- **Fix**: Verify `discord_channel_id` variable is correct
- Get ID: Right-click channel → Copy ID (Developer Mode must be enabled)

**Error**: `HTTP 401: Unauthorized`
- **Fix**: Bot token is invalid or expired
- Solution: Regenerate token in Discord Developer Portal and update Vault

#### GitHub Test Fails

**Error**: `HTTP 404: Not Found`
- **Fix**: Token doesn't have access to `fzymgc-house/selfhosted-cluster`
- Solution: Verify token scopes include `repo`

**Error**: `HTTP 401: Bad credentials`
- **Fix**: Token is invalid or expired
- Solution: Create new token and update Vault

#### S3 Test Fails

**Error**: `No such file or directory: /tmp/windmill-s3-test.txt`
- **Cause**: Windmill worker container doesn't have write access to /tmp
- **Not a problem**: S3 itself may still work, just the local file creation failed

**Error**: `AccessDenied`
- **Fix**: S3 credentials are incorrect
- Solution: Verify access key and secret key in Vault

**Error**: `NoSuchBucket`
- **Fix**: Bucket doesn't exist or name is wrong
- Solution: Create bucket in Storj or verify bucket name

## S3 Credentials Setup

If S3 tests are failing because credentials aren't configured:

### 1. Get Storj S3 Credentials

Follow the guide in `docs/windmill-s3-setup.md` to:
1. Create Storj account
2. Create S3 access grant
3. Get access key and secret key

### 2. Store in Vault

```bash
vault kv patch secret/fzymgc-house/cluster/windmill \
  s3_access_key="<access-key>" \
  s3_secret_key="<secret-key>" \
  s3_bucket="windmill-storage" \
  s3_endpoint="https://gateway.storjshare.io"
```

### 3. Re-sync Variables

```bash
./scripts/sync-vault-to-windmill-vars.sh
```

### 4. Re-run Test

Run `f/terraform/test_configuration` again in Windmill.

## Manual Integration Tests

### Test Discord Notification Manually

```python
import requests

def main():
    discord = wmill.getResource("u/admin/terraform_discord_bot")

    response = requests.post(
        f"https://discord.com/api/v10/channels/{discord['channel_id']}/messages",
        headers={
            "Authorization": f"Bot {discord['bot_token']}",
            "Content-Type": "application/json"
        },
        json={"content": "Manual test from Windmill!"}
    )

    return {
        "success": response.ok,
        "status": response.status_code
    }
```

### Test GitHub Access Manually

```python
import requests

def main():
    github = wmill.getResource("u/admin/github_token")

    response = requests.get(
        "https://api.github.com/repos/fzymgc-house/selfhosted-cluster",
        headers={
            "Authorization": f"token {github['token']}",
            "Accept": "application/vnd.github.v3+json"
        }
    )

    return {
        "success": response.ok,
        "repo_name": response.json().get("full_name") if response.ok else None
    }
```

## Next Steps After Successful Testing

Once all tests pass:

1. ✅ **Configuration validated** - All integrations working
2. → **Phase 3**: Create GitHub Actions workflow for `wmill sync`
3. → **Phase 4**: Test end-to-end Terraform deployment flows
4. → **Phase 5**: Clean up Argo resources
5. → **Phase 6**: Set up monitoring and optimization

## Troubleshooting

### View Script Logs

In Windmill UI:
1. Go to **Runs** tab
2. Find the test_configuration run
3. Click to view detailed logs
4. Check each step's output and errors

### Test Individual Components

Instead of running the full test, you can test each integration separately by modifying the script or using the manual test snippets above.

### Windmill Worker Issues

If scripts aren't running at all:

```bash
# Check Windmill workers are running
kubectl --context fzymgc-house get pods -n windmill -l app=windmill-workers

# Check worker logs
kubectl --context fzymgc-house logs -n windmill -l app=windmill-workers --tail=100
```

## References

- Discord Bot Setup: `docs/windmill-discord-bot-setup.md`
- S3 Storage Setup: `docs/windmill-s3-setup.md`
- GitHub Token Setup: `docs/github-token-setup.md`
- Variable Sync Script: `scripts/sync-vault-to-windmill-vars.sh`

