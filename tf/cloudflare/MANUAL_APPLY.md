# Cloudflare Tunnel Manual Apply Procedure

**Purpose:** Break-glass procedure for applying Cloudflare Tunnel infrastructure when Windmill GitOps workflow is unavailable (initial setup, Windmill downtime, emergencies).

**Use Cases:**
- Initial tunnel setup (Windmill doesn't exist yet)
- Windmill is down or unavailable
- Emergency changes requiring immediate application

---

## Prerequisites

**Required Tools:**
- Terraform >= 1.9.0
- Vault CLI
- kubectl (configured with fzymgc-house context)

**Required Access:**
- Vault token with `infrastructure-developer` policy
- Cloudflare account access (to verify in dashboard)

**Required Cloudflare Setup:**
- Zone `fzymgc.house` must exist and be active (internal services)
- Zone `fzymgc.net` must exist and be active (external webhook services)

---

## Procedure

### Step 1: Authenticate to Vault

```bash
# Set Vault address
export VAULT_ADDR=https://vault.fzymgc.house

# Login with your token
vault login

# Verify your token has infrastructure-developer policy
vault token lookup

# Look for "infrastructure-developer" in policies list
```

**Expected Output:**
```
Key                  Value
---                  -----
policies             [default infrastructure-developer]
```

### Step 2: Get Cloudflare Account ID

You need to update `variables.tf` with your Cloudflare account ID.

**Find Account ID:**
1. Login to Cloudflare Dashboard: https://dash.cloudflare.com
2. Navigate to any domain
3. Look in the right sidebar under "API" section
4. Copy "Account ID"

**Update variables.tf:**
```bash
# Edit tf/cloudflare/variables.tf
# Replace "your-account-id-here" with actual account ID
nano tf/cloudflare/variables.tf
```

### Step 3: Navigate to Module Directory

```bash
cd tf/cloudflare
```

### Step 4: Initialize Terraform

```bash
terraform init
```

**Expected Output:**
```
Initializing the backend...
Initializing provider plugins...
- Finding cloudflare/cloudflare versions matching "~> 4.45"...
- Finding hashicorp/vault versions matching "~> 4.5"...
- Finding hashicorp/random versions matching "~> 3.6"...

Terraform has been successfully initialized!
```

### Step 5: Plan Changes

```bash
terraform plan -out=tfplan
```

**Review Plan Carefully:**
- Check that tunnel name is "fzymgc-house-main"
- Verify DNS records for each webhook service subdomain (e.g., `windmill-wh.fzymgc.net`)
- Confirm Vault path is `secret/fzymgc-house/cluster/cloudflared/tunnels/fzymgc-house-main`
- Ensure ingress rules route subdomains to correct services

**Expected Resources to Create:**
- `random_password.tunnel_secret`
- `cloudflare_tunnel.main`
- `cloudflare_tunnel_config.main`
- `cloudflare_record.webhook_services["windmill"]` (and additional services if configured)
- `vault_kv_secret_v2.tunnel_credentials`

### Step 6: Apply Changes

```bash
terraform apply tfplan
```

**Expected Output:**
```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

tunnel_cname = "<tunnel-id>.cfargotunnel.com"
tunnel_id = "<tunnel-id>"
vault_path = "secret/data/fzymgc-house/cluster/cloudflared/tunnels/fzymgc-house-main"
webhook_urls = {
  "windmill" = "https://windmill-wh.fzymgc.net"
}
```

### Step 7: Verify in Cloudflare Dashboard

1. Go to Cloudflare Dashboard: https://one.dash.cloudflare.com
2. Navigate to **Zero Trust → Networks → Tunnels**
3. Verify tunnel exists: "fzymgc-house-main"
4. Check status: Should show "Inactive" (no connectors yet)
5. Click tunnel name → View configuration
6. Verify ingress rules:
   - Hostname: `windmill-wh.fzymgc.net`
   - Service: `http://windmill.windmill.svc.cluster.local:8000`
   - Additional services if configured (e.g., `argo-wh.fzymgc.net`)

**DNS Verification:**
1. Navigate to **Websites → fzymgc.net → DNS → Records**
2. Verify CNAME records for each webhook service:
   - Name: `windmill-wh`
   - Target: `<tunnel-id>.cfargotunnel.com`
   - Proxy status: Proxied (orange cloud)

### Step 8: Verify Credentials in Vault

```bash
vault kv get secret/fzymgc-house/cluster/cloudflared/tunnels/fzymgc-house-main
```

**Expected Output:**
```
======= Data =======
Key             Value
---             -----
account_tag     <cloudflare-account-id>
tunnel_id       <tunnel-id>
tunnel_name     fzymgc-house-main
tunnel_token    <base64-encoded-token>
```

**All Four Keys Must Be Present:**
- `account_tag`
- `tunnel_id`
- `tunnel_name`
- `tunnel_token` (full token for TUNNEL_TOKEN env var)

### Step 9: Deploy cloudflared (If Not Already Deployed)

```bash
# Return to repository root
cd ../..

# Apply ArgoCD application
kubectl --context fzymgc-house apply -k argocd/app-configs/cloudflared-main/

# Verify ExternalSecret synced
kubectl --context fzymgc-house get externalsecret -n cloudflared
kubectl --context fzymgc-house describe externalsecret cloudflared-credentials -n cloudflared

# Look for: "SecretSynced: True"

# Verify pods running
kubectl --context fzymgc-house get pods -n cloudflared

# Should show 2 replicas in Running state

# Check logs for successful connection
kubectl --context fzymgc-house logs -n cloudflared -l app.kubernetes.io/name=cloudflared --tail=50

# Look for:
# - "Connection established"
# - "Registered tunnel connection"
# - No error messages
```

### Step 10: Verify Tunnel Connection in Dashboard

Return to Cloudflare Dashboard → Zero Trust → Networks → Tunnels

**Check Tunnel Status:**
- Status should now show "Healthy"
- Connectors: Should show 2 active connectors
- Last seen: Should be within last minute

---

## Troubleshooting

### Terraform Init Fails

**Error:** "Could not retrieve credentials from Vault"

**Solution:**
```bash
# Check Vault authentication
vault token lookup

# Re-authenticate if needed
vault login
```

### Terraform Plan Shows Unexpected Changes

**Error:** Plan shows changes to resources that shouldn't change

**Solution:**
- Check if someone else modified the tunnel in Cloudflare Dashboard manually
- Review `terraform show` to see current state
- Investigate differences carefully before applying

### Apply Fails: "Invalid Account ID"

**Error:** "Error creating tunnel: invalid account ID"

**Solution:**
- Verify account ID in `variables.tf` matches Cloudflare Dashboard
- Check Cloudflare API token has correct account permissions

### Vault Write Fails: "Permission Denied"

**Error:** "permission denied" when writing to Vault

**Solution:**
```bash
# Check your token policies
vault token lookup

# Verify infrastructure-developer policy is attached
# If not, request token from Vault administrator
```

---

## Rollback Procedure

**If something goes wrong:**

### Option 1: Delete Specific Resources

```bash
# Delete DNS records only (makes webhooks unreachable)
terraform destroy -target=cloudflare_record.webhook_services

# Delete tunnel config only (keeps tunnel but removes routing)
terraform destroy -target=cloudflare_tunnel_config.main

# Delete entire tunnel
terraform destroy -target=cloudflare_tunnel.main
```

### Option 2: Full Rollback

```bash
terraform destroy
```

**Warning:** This will delete:
- Cloudflare Tunnel
- DNS record
- Vault credentials

**To preserve Vault credentials:** Remove the `vault_kv_secret_v2` resource from state before destroying:

```bash
terraform state rm vault_kv_secret_v2.tunnel_credentials
terraform destroy
```

---

## Re-Syncing to Windmill GitOps

After manual apply, sync changes back to GitOps workflow:

1. Commit Terraform changes to feature branch
2. Create PR and merge to main
3. Windmill will detect changes on next plan
4. Terraform will show "no changes" (infrastructure already matches code)

This ensures Windmill's state matches your manual changes.

---

## Emergency Contacts

- Cloudflare Support: https://dash.cloudflare.com/support
- Vault Documentation: https://vault.fzymgc.house/ui/
- Repository Issues: https://github.com/fzymgc-house/selfhosted-cluster/issues
