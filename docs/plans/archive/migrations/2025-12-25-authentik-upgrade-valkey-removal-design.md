# Authentik 2025.10 Upgrade and Valkey Removal

## Overview

Upgrade Authentik from 2025.6.2 to 2025.10.3 and remove the Valkey (Redis) dependency entirely.

**Current State:**
- Authentik: 2025.6.2 (Helm chart 2025.6.1)
- Valkey: Bitnami Helm chart 3.0.31 (ImagePullBackOff - image tag no longer exists)

**Target State:**
- Authentik: 2025.10.3 (Helm chart 2025.10.3)
- Valkey: Removed entirely

## Rationale

1. **Valkey is broken**: The Bitnami image `docker.io/bitnami/valkey:8.1.3-debian-12-r3` no longer exists on Docker Hub, causing `ImagePullBackOff` errors
2. **Authentik 2025.10 removed Redis**: All features (caching, tasks, WebSocket IPC) now use PostgreSQL
3. **Simplification**: One fewer component to manage, reduced complexity

## Breaking Changes

### Authentik 2025.10 Changes

| Change | Impact | Action Required |
|--------|--------|-----------------|
| Redis removed | Configuration cleanup | Remove `redis.host` and `AUTHENTIK_REDIS__PASSWORD` |
| `email_verified` default changed | OAuth claims | None (downstream apps unaffected) |
| PostgreSQL TLS 1.3 required | None (already using TLS) | Verify PostgreSQL TLS version |

### Migration from 2025.6 → 2025.10

The Redis → PostgreSQL migration was gradual:
- 2024.6: PostgreSQL advisory locks
- 2025.4: Session storage moved to database
- 2025.8: Background tasks revamped (Dramatiq/PostgreSQL)
- 2025.10: Caching and WebSocket IPC moved to PostgreSQL

Since we're jumping from 2025.6 to 2025.10, the upgrade should handle this automatically.

## Implementation Plan

### Phase 1: Update Authentik (Step 1)

**File: `argocd/cluster-app/templates/authentik.yaml`**

Changes:
1. Update `targetRevision` from `2025.6.1` to `2025.10.3`
2. Update `global.image.tag` from `2025.6.2` to `2025.10.3`
3. Remove `authentik.redis.host` configuration

```yaml
# Before
targetRevision: "2025.6.1"
helm:
  valuesObject:
    global:
      image:
        tag: "2025.6.2"
    authentik:
      redis:
        host: valkey-primary.valkey.svc.cluster.local

# After
targetRevision: "2025.10.3"
helm:
  valuesObject:
    global:
      image:
        tag: "2025.10.3"
    # redis section removed entirely
```

### Phase 2: Clean Up ExternalSecret (Step 2)

**File: `argocd/app-configs/authentik/secrets.yaml`**

Remove Valkey-related entries:
1. Remove `AUTHENTIK_REDIS__PASSWORD` from template data
2. Remove `valkey_password` secret reference

```yaml
# Before
template:
  data:
    AUTHENTIK_SECRET_KEY: "{{ .authentik_secret_key }}"
    AUTHENTIK_POSTGRESQL__USER: "{{ .postgres_user }}"
    AUTHENTIK_POSTGRESQL__PASSWORD: "{{ .postgres_password }}"
    AUTHENTIK_REDIS__PASSWORD: "{{ .valkey_password }}"
data:
  - secretKey: valkey_password
    remoteRef:
      key: fzymgc-house/cluster/valkey
      property: password

# After
template:
  data:
    AUTHENTIK_SECRET_KEY: "{{ .authentik_secret_key }}"
    AUTHENTIK_POSTGRESQL__USER: "{{ .postgres_user }}"
    AUTHENTIK_POSTGRESQL__PASSWORD: "{{ .postgres_password }}"
# valkey entries removed
```

### Phase 3: Remove Valkey Application (Step 3)

**Delete: `argocd/cluster-app/templates/valkey.yaml`**

This will trigger ArgoCD to prune the Valkey namespace and all resources.

### Phase 4: Clean Up Valkey App-Configs (Step 4)

**Delete: `argocd/app-configs/valkey/` directory**

Contains ExternalSecret for Valkey password that's no longer needed.

### Phase 5: Vault Cleanup (Optional)

The Vault secret at `fzymgc-house/cluster/valkey` can be archived or deleted since Authentik no longer needs it. However, since it's not causing any issues, this can be deferred.

## Execution Order

1. **Commit 1**: Update Authentik to 2025.10.3 + remove redis config + clean ExternalSecret
2. **Wait**: ArgoCD syncs, verify Authentik health
3. **Commit 2**: Delete Valkey application and app-configs
4. **Wait**: ArgoCD prunes Valkey resources

## Verification

### After Authentik Upgrade

```bash
# Check pod status
kubectl --context fzymgc-house get pods -n authentik

# Check version in logs
kubectl --context fzymgc-house logs -n authentik deployment/authentik-server | grep -i version

# Test authentication flow
# (manual: log into Grafana, Vault, or other OIDC app)
```

### After Valkey Removal

```bash
# Verify namespace is removed
kubectl --context fzymgc-house get ns valkey

# Verify no orphaned resources
kubectl --context fzymgc-house get all -n valkey
```

## Rollback Plan

If issues occur after the Authentik upgrade:

1. Revert the Helm chart version to 2025.6.1
2. Re-add redis configuration
3. Push to main, ArgoCD will sync

Note: Valkey would need to be fixed (image tag updated) for rollback to work.

## New Features Available

Authentik 2025.10 includes:
- SAML and OAuth2 Single Logout (SLO) support
- Telegram authentication source
- SCIM provider OAuth token support (Enterprise)
- RADIUS EAP-TLS support (Enterprise)
- `ak_send_email` in expression policies

## Documentation Updates

After completion:
- Update Notion Services Catalog (remove Valkey entry)
- Update Notion Tech References (Authentik version)
- Archive this design document to `docs/plans/archive/`
