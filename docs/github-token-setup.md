# GitHub Token Setup for Actions Runner Controller

Step-by-step guide to create a GitHub Personal Access Token (PAT) for the actions-runner-controller.

## Prerequisites

- GitHub account with admin access to `fzymgc-house/selfhosted-cluster` repository
- Vault CLI configured and authenticated

## Token Creation Steps

### Option 1: Personal Access Token (Classic) - Simpler

1. **Navigate to GitHub Settings**
   - Go to https://github.com/settings/tokens
   - Or: GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)

2. **Generate New Token**
   - Click "Generate new token" → "Generate new token (classic)"
   - **Note**: Give it a descriptive name like `actions-runner-controller-selfhosted-cluster`
   - **Expiration**: Recommended: 90 days (you'll need to rotate it)

3. **Select Scopes**

   For repository-level runners, select these scopes:

   - ✅ `repo` (Full control of private repositories)
     - Includes: repo:status, repo_deployment, public_repo, repo:invite, security_events
   - ✅ `workflow` (Update GitHub Action workflows)

   **Important**: These are the ONLY two scopes needed.

4. **Generate and Copy Token**
   - Click "Generate token" at the bottom
   - **IMPORTANT**: Copy the token immediately - you won't see it again
   - Token format: `ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

### Option 2: Fine-Grained Personal Access Token - More Secure (Recommended)

1. **Navigate to Fine-Grained Tokens**
   - Go to https://github.com/settings/personal-access-tokens/new
   - Or: GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens

2. **Configure Token**
   - **Token name**: `actions-runner-controller-selfhosted`
   - **Expiration**: 90 days (recommended)
   - **Description**: Self-hosted GitHub Actions runner for Windmill migration
   - **Resource owner**: `fzymgc-house`

3. **Repository Access**
   - Select: **Only select repositories**
   - Choose: `fzymgc-house/selfhosted-cluster`

4. **Permissions**

   Under "Repository permissions":
   - **Actions**: Read and write
   - **Contents**: Read-only
   - **Metadata**: Read-only (automatically selected)
   - **Workflows**: Read and write

   **Note**: Fine-grained tokens provide better security by limiting scope to specific repositories.

5. **Generate and Copy Token**
   - Click "Generate token"
   - Copy the token: `github_pat_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

## Store Token in Vault

Once you have the token:

```bash
# Make sure you're authenticated to Vault
vault token lookup

# Store the token
vault kv put secret/fzymgc-house/cluster/github \
  windmill_actions_runner_token="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

**Verify it was stored:**

```bash
# Check the secret exists (won't show the value)
vault kv get secret/fzymgc-house/cluster/github

# To see the actual token value (if needed for debugging)
vault kv get -field=windmill_actions_runner_token secret/fzymgc-house/cluster/github
```

## Verify Runner Deployment

After storing the token and merging PR #152:

```bash
# Wait for ArgoCD to sync (or manually sync)
kubectl --context fzymgc-house get application actions-runner-controller -n argocd

# Check if ExternalSecret synced the token
kubectl --context fzymgc-house get externalsecret github-token -n actions-runner-system
kubectl --context fzymgc-house get secret github-token -n actions-runner-system

# Check controller deployment
kubectl --context fzymgc-house get pods -n actions-runner-system

# Verify runner registered with GitHub
kubectl --context fzymgc-house get runnerdeployment -n actions-runner-system
kubectl --context fzymgc-house describe runnerdeployment windmill-sync-runner -n actions-runner-system
```

## Verify on GitHub

Check that the runner appears in GitHub:

1. Go to: https://github.com/fzymgc-house/selfhosted-cluster/settings/actions/runners
2. You should see a runner listed with label: `windmill-sync`
3. Status should show as "Idle" (green)

## Token Rotation

Since tokens expire, you'll need to rotate them periodically:

1. Generate a new token following the same steps
2. Update Vault:
   ```bash
   vault kv patch secret/fzymgc-house/cluster/github \
     windmill_actions_runner_token="<new-token>"
   ```
3. ExternalSecret will automatically sync the new token
4. Runner pods will automatically use the new token

## Troubleshooting

### Token Not Working

```bash
# Check controller logs
kubectl --context fzymgc-house logs -n actions-runner-system \
  -l app.kubernetes.io/name=actions-runner-controller --tail=100

# Common errors:
# - "401 Unauthorized": Token invalid or expired
# - "403 Forbidden": Insufficient permissions
# - "404 Not Found": Repository access not granted
```

### Runner Not Appearing in GitHub

1. **Check token scopes**: Must have `repo` and `workflow` (classic) or equivalent fine-grained permissions
2. **Verify repository access**: Token must have access to `fzymgc-house/selfhosted-cluster`
3. **Check controller status**: `kubectl get pods -n actions-runner-system`
4. **Review logs**: Look for authentication errors in controller logs

### ExternalSecret Not Syncing

```bash
# Check ExternalSecret status
kubectl --context fzymgc-house describe externalsecret github-token -n actions-runner-system

# Common issues:
# - Vault path wrong: Should be secret/fzymgc-house/cluster/github
# - Vault key wrong: Should be windmill_actions_runner_token
# - ClusterSecretStore not configured: Check 'vault' ClusterSecretStore exists
```

## Security Considerations

- **Token Storage**: Never commit tokens to Git. Always use Vault.
- **Token Scope**: Use minimum required scopes. Fine-grained tokens are more secure.
- **Token Expiration**: Set reasonable expiration (90 days recommended).
- **Token Rotation**: Have a process to rotate before expiration.
- **Access Control**: Limit who can access the Vault secret.

## Token Comparison

| Feature | Classic PAT | Fine-Grained PAT |
|---------|-------------|------------------|
| Scope | All repos user has access to | Specific repositories only |
| Permissions | Broad (`repo`, `workflow`) | Granular (Actions, Workflows, etc.) |
| Expiration | Custom (max 1 year) | Custom (max 1 year) |
| Security | Lower | Higher (recommended) |
| Setup | Simpler | More complex |

**Recommendation**: Use Fine-Grained PAT for better security.

## References

- GitHub PAT Documentation: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
- Actions Runner Controller: https://github.com/actions/actions-runner-controller
- Self-Hosted Runners: https://docs.github.com/en/actions/hosting-your-own-runners
