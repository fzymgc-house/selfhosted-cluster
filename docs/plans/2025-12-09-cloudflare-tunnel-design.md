# Cloudflare Tunnel Design

**Date:** 2025-12-09
**Issue:** #215 - Add Cloudflare Tunnel for public service exposure
**Author:** Claude Code
**Status:** Implemented (PRs #259, #260)

## Overview

Deploy Cloudflare Tunnel infrastructure to expose internal Kubernetes services to the internet without inbound firewall rules. Initial use case: expose Windmill webhook endpoints at `windmill.wh.fzymgc.house` for Discord approval buttons using subdomain-based routing.

## Problem Statement

Issue #237 requires testing the Discord approval flow for Windmill Terraform deployments. The current implementation uses Discord buttons with `custom_id`, which require a Discord interactions endpoint that doesn't exist. The solution (per Discord approval design doc) is to use Link-style buttons that make HTTP requests to Windmill's resume/cancel URLs.

**Challenge:** Discord servers need to reach Windmill's webhook endpoints from the internet. Current Windmill instance is internal-only (accessible via Tailscale or Traefik IngressRoute within cluster).

**Solution:** Expose Windmill webhook endpoints via Cloudflare Tunnel at `windmill.wh.fzymgc.house` using subdomain-based routing. This approach avoids Cloudflare Free plan limitations with Transform Rules (regex_replace requires Business plan) and provides cleaner service isolation.

## Requirements

### Functional Requirements

1. **Webhook Exposure**: Expose Windmill webhook endpoints (`/api/w/*/jobs_u/*`) publicly
2. **Subdomain Isolation**: Use `service.wh.fzymgc.house` subdomain pattern for clear service separation
3. **Future Extensibility**: Support adding other services (e.g., `argo.wh.fzymgc.house`)
4. **No Authentication Layer**: Discord can't handle OAuth/service tokens; security is in Windmill's signed URLs
5. **High Availability**: Multiple cloudflared replicas for redundancy
6. **No Path Rewriting**: Works on Cloudflare Free plan (no Transform Rules needed)

### Non-Functional Requirements

1. **GitOps Workflow**: Infrastructure as code via Terraform and ArgoCD
2. **Break-Glass Procedure**: Manual Terraform apply for bootstrapping and emergencies
3. **Vault Integration**: Credentials stored in Vault, not Kubernetes secrets
4. **Monitoring**: Logs and metrics for tunnel connectivity
5. **Rollback Plan**: Clear procedure to revert if issues occur

## Architecture

### High-Level Flow

```
GitHub PR merge → Windmill Flow → Terraform Apply
                                      ↓
                        Creates: Tunnel + DNS + Vault Creds
                                      ↓
                        Vault ExternalSecret → K8s Secret
                                      ↓
                        ArgoCD deploys cloudflared Deployment
                                      ↓
                        cloudflared connects to tunnel
                                      ↓
                Discord → windmill.wh.fzymgc.house → Windmill
```

### Components

#### 1. Terraform Module (`tf/cloudflare/`)

**Purpose:** Manage Cloudflare Tunnel infrastructure as code

**Resources:**
- `cloudflare_tunnel.main` - Creates tunnel named "fzymgc-house-main"
- `cloudflare_tunnel_config.main` - Configures ingress rules with subdomain-based routing
- `cloudflare_record.webhook_services` - DNS CNAME records for each webhook service subdomain
- `vault_kv_secret_v2.tunnel_credentials` - Stores credentials in Vault

**Variables:**
```hcl
variable "webhook_services" {
  description = "Map of webhook services with their subdomain and upstream configuration"
  type = map(object({
    service_url = string
  }))
  default = {
    windmill = {
      service_url = "http://windmill.windmill.svc.cluster.local:8000"
    }
  }
}
```

**Ingress Rules:**
```hcl
config {
  # Dynamic ingress rules for webhook services
  # Each service gets its own subdomain: service.wh.fzymgc.house
  dynamic "ingress_rule" {
    for_each = var.webhook_services
    content {
      hostname = "${ingress_rule.key}.${var.webhook_base_domain}"
      service  = ingress_rule.value.service_url

      origin_request {
        http_host_header   = "${ingress_rule.key}.${var.webhook_base_domain}"
        origin_server_name = split("//", ingress_rule.value.service_url)[1]
        no_tls_verify      = false
      }
    }
  }

  # Catch-all rule (required by cloudflared)
  ingress_rule {
    service = "http_status:404"
  }
}
```

**Vault Storage Path:**
```
secret/fzymgc-house/cluster/cloudflared/tunnels/fzymgc-house-main/
  ├── account_tag
  ├── tunnel_id
  ├── tunnel_name
  └── tunnel_token   # Full token for TUNNEL_TOKEN env var (base64-encoded JSON with {a,t,s})
```

**Rationale:** Multi-tunnel path structure allows future tunnels at `.../tunnels/<tunnel-name>/`

> **Important:** The `tunnel_token` is the full authentication token computed by Cloudflare for token-based authentication. This is the recommended approach for remotely-managed tunnels where ingress rules are configured via Terraform/API rather than a local config file.

#### 2. ArgoCD Application (`argocd/app-configs/cloudflared-main/`)

**Purpose:** Deploy cloudflared connector pods

**Structure:**
```
cloudflared-main/
├── kustomization.yaml
├── namespace.yaml
├── external-secret.yaml
├── service-account.yaml
├── deployment.yaml
└── service.yaml  # For metrics/health checks
```

**ExternalSecret:**
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: cloudflared-credentials
  namespace: cloudflared
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: cloudflared-credentials
    creationPolicy: Owner
  data:
    # Full tunnel token for TUNNEL_TOKEN env var (token-based auth)
    # This is the recommended approach for remotely-managed tunnels
    - secretKey: tunnel_token
      remoteRef:
        key: fzymgc-house/cluster/cloudflared/tunnels/fzymgc-house-main
        property: tunnel_token
```

> **Note:** Token-based authentication is simpler than `credentials.json`. The `tunnel_token` contains all necessary authentication data (account tag, tunnel ID, and secret) encoded into a single value that cloudflared understands via the `TUNNEL_TOKEN` environment variable.

**Deployment:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: cloudflared
spec:
  replicas: 2  # High availability
  selector:
    matchLabels:
      app.kubernetes.io/name: cloudflared
  template:
    metadata:
      labels:
        app.kubernetes.io/name: cloudflared
    spec:
      serviceAccountName: cloudflared
      containers:
      - name: cloudflared
        image: cloudflare/cloudflared:2025.11.1
        args:
          - tunnel
          - --loglevel
          - debug
          - --metrics
          - 0.0.0.0:2000
          - --no-autoupdate
          - run
        env:
          # Token-based auth for remotely-managed tunnels
          # Ingress rules are managed in Cloudflare via Terraform
          - name: TUNNEL_TOKEN
            valueFrom:
              secretKeyRef:
                name: cloudflared-credentials
                key: tunnel_token
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
        livenessProbe:
          httpGet:
            path: /ready
            port: 2000
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 2000
          initialDelaySeconds: 5
          periodSeconds: 5
        securityContext:
          runAsNonRoot: true
          runAsUser: 65532
          runAsGroup: 65532
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
```

> **Important:** The deployment uses `TUNNEL_TOKEN` environment variable directly, not `--token` flag with `credentials.json`. When cloudflared detects `TUNNEL_TOKEN` in the environment, it authenticates and fetches configuration from Cloudflare automatically.

### Security Model

**Transport Security:**
- Cloudflare Tunnel provides encrypted connection (no inbound firewall rules needed)
- TLS termination at Cloudflare edge
- Encrypted tunnel from Cloudflare to cluster

**Authentication:**
- **No Cloudflare Access**: Discord can't handle OAuth flows or service tokens
- **Windmill Signed URLs**: Authentication built into resume/cancel URLs (the `resume_id` is the secret)
- **Defense-in-Depth**: Even if someone gets the URL, it's single-use and time-limited

**Subdomain Security:**
- Only `windmill.wh.fzymgc.house` exposed publicly (webhook endpoints only)
- Full Windmill UI remains internal (Traefik IngressRoute at `windmill.fzymgc.house`)
- Each service requires explicit subdomain configuration in Terraform
- Subdomain isolation prevents accidental exposure of other services

## Deployment Modes

### 1. Standard Flow (GitOps via Windmill)

**Use Case:** Day-to-day configuration changes

**Process:**
1. Create PR with Terraform changes
2. Merge to main
3. GitHub Action triggers Windmill flow
4. Windmill runs `terraform plan` → sends to Discord
5. Approve via Discord button
6. Windmill runs `terraform apply`
7. ArgoCD syncs cloudflared deployment if needed

**Benefits:**
- Follows existing pattern (Vault, Grafana, Authentik use this flow)
- Discord approval provides visibility
- Full audit trail

### 2. Manual Break-Glass (Direct Terraform)

**Use Case:**
- Initial setup (Windmill doesn't exist yet)
- Windmill downtime
- Emergency changes

**Procedure:**

```bash
# Step 1: Authenticate to Vault
export VAULT_ADDR=https://vault.fzymgc.house
vault login
# Use token with infrastructure-developer policy

# Step 2: Navigate to module
cd tf/cloudflare

# Step 3: Run Terraform
terraform init
terraform plan -out=tfplan
# Review plan carefully
terraform apply tfplan

# Step 4: Verify in Cloudflare Dashboard
# - Check tunnel exists: "fzymgc-house-main"
# - Check DNS record: wh.fzymgc.house → <tunnel-id>.cfargotunnel.com
# - Check ingress rules configured

# Step 5: Verify in Vault
vault kv get secret/fzymgc-house/cluster/cloudflared/tunnels/fzymgc-house-main
# Should show account_tag, tunnel_id, tunnel_name, tunnel_secret

# Step 6: Trigger ArgoCD sync
kubectl --context fzymgc-house apply -k argocd/app-configs/cloudflared-main/
# Or sync via ArgoCD UI

# Step 7: Verify pods running
kubectl --context fzymgc-house get pods -n cloudflared
kubectl --context fzymgc-house logs -n cloudflared -l app=cloudflared
# Look for: "Connection established" and "Registered tunnel"
```

**Documentation:** This procedure will be documented in `tf/cloudflare/MANUAL_APPLY.md`

## Testing and Rollout

### Phase 1: Terraform Apply (Break-Glass)

**Goal:** Create tunnel infrastructure

```bash
# Manual apply to bootstrap
cd tf/cloudflare
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

**Verification:**
- Cloudflare Dashboard: Tunnel "fzymgc-house-main" exists
- Cloudflare Dashboard: DNS record `windmill.wh.fzymgc.house` points to tunnel
- Cloudflare Dashboard: Ingress rules show `windmill.wh.fzymgc.house` → Windmill service
- Vault: `vault kv get secret/fzymgc-house/cluster/cloudflared/tunnels/fzymgc-house-main`

### Phase 2: Deploy cloudflared

**Goal:** Deploy connector pods that establish tunnel connection

```bash
# Apply ArgoCD application
kubectl --context fzymgc-house apply -k argocd/app-configs/cloudflared-main/

# Verify ExternalSecret synced
kubectl --context fzymgc-house get externalsecret -n cloudflared
kubectl --context fzymgc-house describe externalsecret cloudflared-credentials -n cloudflared
# Should show: "SecretSynced: True"

# Verify secret created
kubectl --context fzymgc-house get secret cloudflared-credentials -n cloudflared

# Verify pods running
kubectl --context fzymgc-house get pods -n cloudflared
# Should show 2 replicas running

# Check logs for successful connection
kubectl --context fzymgc-house logs -n cloudflared -l app=cloudflared
# Look for:
# - "Connection established"
# - "Registered tunnel connection"
# - No error messages
```

### Phase 3: Test Webhook Endpoint

**Goal:** Verify external connectivity and subdomain routing

**Test from external network** (not through Tailscale):

```bash
# Test valid Windmill endpoint
curl -v https://windmill.wh.fzymgc.house/api/version
# Expected: 200 OK with Windmill version JSON

# Test path that doesn't exist in Windmill
curl -v https://windmill.wh.fzymgc.house/nonexistent
# Expected: Windmill's 404 response (confirms routing to Windmill)

# Test non-configured subdomain
curl -v https://other.wh.fzymgc.house/api/version
# Expected: Tunnel 404 (no matching ingress rule)

# Test base domain
curl -v https://wh.fzymgc.house/
# Expected: DNS resolution may fail or tunnel 404 (no ingress rule)
```

### Phase 4: Update Discord Approval URLs

**Goal:** Integrate with Discord approval flow

```bash
# Update windmill/f/terraform/notify_approval.py
# Change public_domain from "windmill.fzymgc.house" to "windmill.wh.fzymgc.house"
# No path prefix needed - subdomain routing is direct to Windmill

# Test with safe Terraform change
# Trigger deploy_vault flow
# Verify Discord buttons have correct URLs
# Click approve, verify Windmill resumes flow
```

### Rollback Plan

**If tunnel doesn't connect:**
- Check cloudflared pod logs for errors
- Verify credentials in Vault match Cloudflare dashboard
- Check ExternalSecret sync status
- Restart cloudflared pods: `kubectl rollout restart -n cloudflared deployment/cloudflared`

**If DNS doesn't resolve:**
- Verify DNS record in Cloudflare dashboard
- Check `proxied=true` (orange cloud enabled)
- Wait up to 5 minutes for DNS propagation
- Test with `dig wh.fzymgc.house` or `nslookup wh.fzymgc.house`

**If subdomain routing broken:**
- Review ingress rules in Cloudflare Tunnel dashboard
- Check Terraform config for typos in hostname or service URL
- Verify DNS records created correctly (`windmill.wh.fzymgc.house`)
- Fix in Terraform, re-apply
- cloudflared automatically picks up config changes

**Emergency rollback:**
- Delete DNS records in Cloudflare: `terraform destroy -target=cloudflare_record.webhook_services`
- Windmill reverts to internal-only access
- Discord approval buttons won't work, but Windmill UI still accessible via Tailscale

### Troubleshooting

#### Authentication Method: Token vs credentials.json

There are two authentication methods for cloudflared:

1. **credentials.json** (locally-managed tunnels):
   - File contains `AccountTag`, `TunnelID`, `TunnelName`, and `TunnelSecret`
   - `TunnelSecret` must be the **raw base64-encoded secret value only**
   - Ingress rules configured via local config file

2. **TUNNEL_TOKEN** (remotely-managed tunnels - **recommended**):
   - Environment variable contains full authentication token
   - Token format: base64-encoded JSON with `{a: accountTag, t: tunnelSecret, s: tunnelId}`
   - Ingress rules configured in Cloudflare dashboard or via API/Terraform

**Common Error:** "control stream encountered a failure while serving"

This error occurs when using `credentials.json` but the `TunnelSecret` field contains the full tunnel token (with `{a,t,s}`) instead of just the raw secret value. The solution is to use token-based auth with `TUNNEL_TOKEN` environment variable.

**Lesson Learned (PRs #253-#260):** Initially tried `credentials.json` approach, but the Terraform provider's `tunnel_token` attribute returns the full token (for `TUNNEL_TOKEN` env var), not the raw `TunnelSecret` value. Switching to token-based auth resolved the issue.

#### Terraform State Issues

If Terraform wants to recreate the tunnel (destroy + create), add lifecycle rules:

```hcl
resource "cloudflare_zero_trust_tunnel_cloudflared" "main" {
  # ...

  lifecycle {
    ignore_changes = [secret]
  }
}
```

If `random_password.tunnel_secret` is not in state but Terraform expects it:

```bash
terraform import random_password.tunnel_secret "$(openssl rand -base64 48 | tr -d '\n')"
```

### Monitoring

**cloudflared pod logs:**
```bash
kubectl --context fzymgc-house logs -n cloudflared -l app=cloudflared -f
```
Watch for:
- "Connection established"
- "Registered tunnel connection"
- HTTP status codes from requests

**Cloudflare Dashboard:**
- Navigate to Zero Trust → Access → Tunnels
- Select "fzymgc-house-main"
- View metrics: Requests, Data transfer, Active connections

**Windmill access logs:**
- Check Windmill logs for incoming webhook requests
- Verify requests coming from Cloudflare IPs

## Future Enhancements

### Additional Services

To expose more services, add them to the `webhook_services` variable in `tf/cloudflare/variables.tf`:

```hcl
variable "webhook_services" {
  default = {
    windmill = {
      service_url = "http://windmill.windmill.svc.cluster.local:8000"
    }
    argo = {
      service_url = "http://argo-server.argo.svc.cluster.local:2746"
    }
  }
}
```

This automatically creates:
- DNS records: `argo.wh.fzymgc.house` → tunnel CNAME
- Ingress rules: `argo.wh.fzymgc.house` → Argo service

Then apply via Terraform workflow.

### Multiple Tunnels

For isolation or different use cases, create additional tunnels:

1. **Create new Terraform resource:**
```hcl
resource "cloudflare_tunnel" "public" {
  account_id = var.cloudflare_account_id
  name       = "fzymgc-house-public"
  secret     = random_password.public_tunnel_secret.result
}
```

2. **Store credentials:**
```
secret/fzymgc-house/cluster/cloudflared/tunnels/fzymgc-house-public/
```

3. **Deploy new ArgoCD app:**
```
argocd/app-configs/cloudflared-public/
```

### Cloudflare Access Integration

If future services need authentication (unlike Windmill webhooks):

```hcl
# Add to Terraform
resource "cloudflare_access_application" "protected_service" {
  zone_id          = data.cloudflare_zone.fzymgc_house.id
  name             = "Protected Service"
  domain           = "protected.fzymgc.house"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_access_policy" "protected_service" {
  application_id = cloudflare_access_application.protected_service.id
  name           = "Allow authenticated users"
  precedence     = 1
  decision       = "allow"

  include {
    email_domain = ["fzymgc.house"]
  }
}
```

## Dependencies

**Blocked by:** None

**Blocks:**
- #237 - Test end-to-end Discord approval flow (requires webhook endpoint)
- Discord approval design implementation (requires `wh.fzymgc.house` to exist)

**Related:**
- Discord approval design (docs/plans/2025-12-08-discord-approval-design.md)
- Windmill GitOps migration (docs/windmill-migration.md)

## Implementation Checklist

- [x] Create `tf/cloudflare/tunnel.tf` with tunnel resources
- [ ] Create `tf/cloudflare/MANUAL_APPLY.md` with break-glass procedure
- [x] Update Cloudflare API token permissions if needed
- [x] Run manual Terraform apply (Phase 1)
- [x] Verify tunnel in Cloudflare dashboard
- [x] Verify credentials in Vault
- [x] Create `argocd/app-configs/cloudflared-main/` directory
- [x] Create Kubernetes manifests (namespace, ExternalSecret, deployment)
- [x] Deploy via ArgoCD (Phase 2)
- [x] Verify pods running and connected (4 connections to Cloudflare edge)
- [ ] Test webhook endpoint externally (Phase 3)
- [ ] Update Discord approval code (Phase 4)
- [ ] Test full Discord approval flow
- [x] Document any issues encountered (see Troubleshooting section)
- [ ] Add monitoring/alerting for tunnel health

## Open Questions

None - implementation complete and working.

## Implementation Notes

**PRs:**
- #259: Initial token-based auth implementation
- #260: Terraform lifecycle fix to prevent tunnel recreation

**Verified Working (2025-12-09):**
- 2 cloudflared pods running in HA configuration
- 4 tunnel connections registered to Cloudflare edge (iad05, iad07, iad16)
- ExternalSecret syncing `tunnel_token` from Vault
- Ingress rules configured via Terraform for `windmill.wh.fzymgc.house`
