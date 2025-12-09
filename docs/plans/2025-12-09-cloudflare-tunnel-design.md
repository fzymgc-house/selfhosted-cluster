# Cloudflare Tunnel Design

**Date:** 2025-12-09
**Issue:** #215 - Add Cloudflare Tunnel for public service exposure
**Author:** Claude Code
**Status:** Design Phase

## Overview

Deploy Cloudflare Tunnel infrastructure to expose internal Kubernetes services to the internet without inbound firewall rules. Initial use case: expose Windmill webhook endpoints at `wh.fzymgc.house/windmill/*` for Discord approval buttons.

## Problem Statement

Issue #237 requires testing the Discord approval flow for Windmill Terraform deployments. The current implementation uses Discord buttons with `custom_id`, which require a Discord interactions endpoint that doesn't exist. The solution (per Discord approval design doc) is to use Link-style buttons that make HTTP requests to Windmill's resume/cancel URLs.

**Challenge:** Discord servers need to reach Windmill's webhook endpoints from the internet. Current Windmill instance is internal-only (accessible via Tailscale or Traefik IngressRoute within cluster).

**Solution:** Expose Windmill webhook endpoints via Cloudflare Tunnel at `wh.fzymgc.house/windmill/*`.

## Requirements

### Functional Requirements

1. **Webhook Exposure**: Expose Windmill webhook endpoints (`/api/w/*/jobs_u/*`) publicly
2. **Path Namespacing**: Use `/windmill/*` prefix for clear service separation
3. **Future Extensibility**: Support adding other services (e.g., `/other-service/*`)
4. **No Authentication Layer**: Discord can't handle OAuth/service tokens; security is in Windmill's signed URLs
5. **High Availability**: Multiple cloudflared replicas for redundancy

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
                Discord → wh.fzymgc.house/windmill/* → Windmill
```

### Components

#### 1. Terraform Module (`tf/cloudflare/`)

**Purpose:** Manage Cloudflare Tunnel infrastructure as code

**Resources:**
- `cloudflare_tunnel.main` - Creates tunnel named "fzymgc-house-main"
- `cloudflare_tunnel_config.main` - Configures ingress rules with path routing
- `cloudflare_record.webhook` - DNS CNAME record for `wh.fzymgc.house`
- `vault_kv_secret_v2.tunnel_credentials` - Stores credentials in Vault

**Ingress Rules:**
```hcl
config {
  # Windmill webhooks with path rewriting
  ingress_rule {
    hostname = "wh.fzymgc.house"
    path     = "/windmill/*"
    service  = "http://windmill.windmill.svc.cluster.local:8000"
    origin_request {
      http_host_header = "windmill.windmill.svc.cluster.local"
      origin_server_name = "windmill.windmill.svc.cluster.local"
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
  └── tunnel_secret
```

**Rationale:** Multi-tunnel path structure allows future tunnels at `.../tunnels/<tunnel-name>/`

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
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cloudflared-credentials
  namespace: cloudflared
spec:
  refreshInterval: 15s
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: cloudflared-credentials
    creationPolicy: Owner
    template:
      type: Opaque
      data:
        credentials.json: |
          {
            "AccountTag": "{{ .account_tag }}",
            "TunnelID": "{{ .tunnel_id }}",
            "TunnelName": "{{ .tunnel_name }}",
            "TunnelSecret": "{{ .tunnel_secret }}"
          }
  data:
    - secretKey: account_tag
      remoteRef:
        key: fzymgc-house/cluster/cloudflared/tunnels/fzymgc-house-main
        property: account_tag
    - secretKey: tunnel_id
      remoteRef:
        key: fzymgc-house/cluster/cloudflared/tunnels/fzymgc-house-main
        property: tunnel_id
    - secretKey: tunnel_name
      remoteRef:
        key: fzymgc-house/cluster/cloudflared/tunnels/fzymgc-house-main
        property: tunnel_name
    - secretKey: tunnel_secret
      remoteRef:
        key: fzymgc-house/cluster/cloudflared/tunnels/fzymgc-house-main
        property: tunnel_secret
```

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
      app: cloudflared
  template:
    metadata:
      labels:
        app: cloudflared
    spec:
      serviceAccountName: cloudflared
      containers:
      - name: cloudflared
        image: cloudflare/cloudflared:latest
        args:
          - tunnel
          - --no-autoupdate
          - run
          - --token
          - "$(TUNNEL_TOKEN)"
        env:
        - name: TUNNEL_TOKEN
          valueFrom:
            secretKeyRef:
              name: cloudflared-credentials
              key: credentials.json
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
```

### Security Model

**Transport Security:**
- Cloudflare Tunnel provides encrypted connection (no inbound firewall rules needed)
- TLS termination at Cloudflare edge
- Encrypted tunnel from Cloudflare to cluster

**Authentication:**
- **No Cloudflare Access**: Discord can't handle OAuth flows or service tokens
- **Windmill Signed URLs**: Authentication built into resume/cancel URLs (the `resume_id` is the secret)
- **Defense-in-Depth**: Even if someone gets the URL, it's single-use and time-limited

**Path Security:**
- Only `/windmill/*` exposed publicly
- Full Windmill UI remains internal (Traefik IngressRoute)
- Future services explicitly configured in Terraform

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
- Cloudflare Dashboard: DNS record `wh.fzymgc.house` points to tunnel
- Cloudflare Dashboard: Ingress rules show `/windmill/*` → Windmill service
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

**Goal:** Verify external connectivity and path routing

**Test from external network** (not through Tailscale):

```bash
# Test valid Windmill endpoint
curl -v https://wh.fzymgc.house/windmill/api/version
# Expected: 200 OK with Windmill version JSON

# Test path that doesn't exist in Windmill
curl -v https://wh.fzymgc.house/windmill/nonexistent
# Expected: Windmill's 404 response (confirms routing to Windmill)

# Test without /windmill prefix
curl -v https://wh.fzymgc.house/api/version
# Expected: Tunnel 404 (no matching ingress rule)

# Test root path
curl -v https://wh.fzymgc.house/
# Expected: Tunnel 404 (no matching ingress rule)
```

### Phase 4: Update Discord Approval URLs

**Goal:** Integrate with Discord approval flow

```bash
# Update windmill/f/terraform/notify_approval.py
# Change public_domain from "windmill.fzymgc.house" to "wh.fzymgc.house"
# Update make_public_url() to add "/windmill" prefix

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

**If path routing broken:**
- Review ingress rules in Cloudflare Tunnel dashboard
- Check Terraform config for typos in service URL
- Fix in Terraform, re-apply
- cloudflared automatically picks up config changes

**Emergency rollback:**
- Delete DNS record in Cloudflare: `terraform destroy -target=cloudflare_record.webhook`
- Windmill reverts to internal-only access
- Discord approval buttons won't work, but Windmill UI still accessible via Tailscale

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

To expose more services, add ingress rules to `tf/cloudflare/tunnel.tf`:

```hcl
# Example: Public documentation site
ingress_rule {
  hostname = "docs.fzymgc.house"
  service  = "http://docs.default.svc.cluster.local:8080"
}
```

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

- [ ] Create `tf/cloudflare/tunnel.tf` with tunnel resources
- [ ] Create `tf/cloudflare/MANUAL_APPLY.md` with break-glass procedure
- [ ] Update Cloudflare API token permissions if needed
- [ ] Run manual Terraform apply (Phase 1)
- [ ] Verify tunnel in Cloudflare dashboard
- [ ] Verify credentials in Vault
- [ ] Create `argocd/app-configs/cloudflared-main/` directory
- [ ] Create Kubernetes manifests (namespace, ExternalSecret, deployment)
- [ ] Deploy via ArgoCD (Phase 2)
- [ ] Verify pods running and connected
- [ ] Test webhook endpoint externally (Phase 3)
- [ ] Update Discord approval code (Phase 4)
- [ ] Test full Discord approval flow
- [ ] Document any issues encountered
- [ ] Add monitoring/alerting for tunnel health

## Open Questions

None - design validated and ready for implementation.
