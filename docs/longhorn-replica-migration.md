# Longhorn Replica Migration Plan

## Overview

This document outlines the plan to increase Longhorn storage replication from 2 to 3 replicas for high availability and migrate strict-local volumes to replicated storage.

## Current State

- **Storage Class**: `longhorn-retain` configured with `numberOfReplicas: "2"`
- **Active Volumes**: 32 total volumes
  - 24 volumes with 2 replicas (now upgraded to 3)
  - 1 volume with strict-local (1 replica): `teleport/teleport-db-1`
  - 7 detached/orphaned volumes with strict-local (can be deleted)

## Changes Applied

### 1. Storage Class Update
- Updated `argocd/app-configs/shared-resources/longhorn-storage-classes.yaml`
- Changed `numberOfReplicas` from `"2"` to `"3"`
- New PVCs will automatically get 3 replicas

### 2. Existing Volume Updates
- Successfully updated 24 volumes from 2 to 3 replicas
- Volumes are replicating to third replica automatically via Longhorn

## Strict-Local Volume Migration

### Active Volume: teleport/teleport-db-1

**Current Configuration:**
- PVC: `teleport/teleport-db-1`
- Volume: `pvc-aa2d6a02-4fdd-4262-8b0d-d8fa79010f46`
- StorageClass: `postgres-storage`
- Data Locality: `strict-local` (manually set)
- Replicas: 1

**Source:**
- Managed by CloudNativePG Cluster: `teleport/teleport-db`
- PostgreSQL database for Teleport
- Single instance database (`instances: 1`)

**Migration Strategy:**

The Teleport PostgreSQL volume was manually configured with `strict-local` data locality, overriding the StorageClass default of `best-effort`. To migrate to 3 replicas:

#### Option A: Update Volume Directly (Recommended)
1. Patch the volume to change `dataLocality` from `strict-local` to `best-effort`
2. Patch the volume to set `numberOfReplicas` to `3`
3. Longhorn will automatically create additional replicas
4. Minimal downtime (volume remains attached)

```bash
# Step 1: Change data locality
kubectl --context fzymgc-house patch volume.longhorn.io pvc-aa2d6a02-4fdd-4262-8b0d-d8fa79010f46 \
  -n longhorn-system --type='json' \
  -p='[{"op": "replace", "path": "/spec/dataLocality", "value": "best-effort"}]'

# Step 2: Increase replicas
kubectl --context fzymgc-house patch volume.longhorn.io pvc-aa2d6a02-4fdd-4262-8b0d-d8fa79010f46 \
  -n longhorn-system --type='json' \
  -p='[{"op": "replace", "path": "/spec/numberOfReplicas", "value": 3}]'

# Step 3: Monitor replication progress
kubectl --context fzymgc-house get volume.longhorn.io pvc-aa2d6a02-4fdd-4262-8b0d-d8fa79010f46 \
  -n longhorn-system -o jsonpath='{.status.robustness}'
```

#### Option B: Recreate Volume (Higher Risk)
1. Create backup of PostgreSQL database
2. Delete the PVC and allow CloudNativePG to recreate
3. Restore from backup
4. Higher downtime and complexity

**Recommendation:** Use Option A - direct volume update with minimal downtime.

### Orphaned Volumes (Cleanup)

These 7 detached volumes are from deleted PVCs and can be safely removed:

- `pvc-2c1f9d32-12d6-4e69-b5d2-f01c1591ccc6`
- `pvc-3429f8d6-4d27-44ca-a7c2-35d33862025b`
- `pvc-41babba2-1a4f-469a-bf7e-f4a2-1b92152`
- `pvc-4aaaf630-036c-4914-ad0c-d9d83d567cea`
- `pvc-b143c9bc-4cfe-41cc-bf2c-4dda0d8634a8`
- `pvc-db8b4b70-1fb7-43c3-a9ee-287bcbde8a73`
- `pvc-ee7385a2-f3e7-417d-b15a-38f6ce7dc81f`

**Cleanup Command:**
```bash
for vol in pvc-2c1f9d32-12d6-4e69-b5d2-f01c1591ccc6 \
           pvc-3429f8d6-4d27-44ca-a7c2-35d33862025b \
           pvc-41babba2-1a4f-469a-bf7e-f4a2-1b92152 \
           pvc-4aaaf630-036c-4914-ad0c-d9d83d567cea \
           pvc-b143c9bc-4cfe-41cc-bf2c-4dda0d8634a8 \
           pvc-db8b4b70-1fb7-43c3-a9ee-287bcbde8a73 \
           pvc-ee7385a2-f3e7-417d-b15a-38f6ce7dc81f; do
  kubectl --context fzymgc-house delete volume.longhorn.io $vol -n longhorn-system
done
```

## Storage Class Updates Required

Update `argocd/app-configs/cnpg/storageclass-postgres.yaml` to match new replica count:

```yaml
parameters:
  numberOfReplicas: "3"  # Changed from "2"
```

## Verification Steps

After migration:

1. **Verify storage class replica counts:**
   ```bash
   kubectl --context fzymgc-house get storageclass -o json | \
     jq -r '.items[] | select(.provisioner == "driver.longhorn.io") | "\(.metadata.name): replicas=\(.parameters.numberOfReplicas)"'
   ```

2. **Verify all active volumes have 3 replicas:**
   ```bash
   kubectl --context fzymgc-house get volumes.longhorn.io -n longhorn-system -o json | \
     jq -r '.items[] | select(.status.state == "attached") | "\(.metadata.name): replicas=\(.spec.numberOfReplicas), locality=\(.spec.dataLocality)"'
   ```

3. **Check volume health:**
   ```bash
   kubectl --context fzymgc-house get volumes.longhorn.io -n longhorn-system -o json | \
     jq -r '.items[] | select(.status.state == "attached") | "\(.metadata.name): \(.status.robustness)"'
   ```

## Rollback Plan

If issues occur:

1. **Revert storage class changes:**
   ```bash
   git checkout main -- argocd/app-configs/shared-resources/longhorn-storage-classes.yaml
   git checkout main -- argocd/app-configs/cnpg/storageclass-postgres.yaml
   ```

2. **Reduce volume replicas:**
   ```bash
   # This will NOT delete existing data, just reduce replica count
   kubectl --context fzymgc-house patch volume.longhorn.io <volume-name> \
     -n longhorn-system --type='json' \
     -p='[{"op": "replace", "path": "/spec/numberOfReplicas", "value": 2}]'
   ```

## Timeline

1. **Immediate**: Storage class updates committed and merged (this PR)
2. **Post-merge**: Update postgres-storage StorageClass via GitOps
3. **Scheduled maintenance window**: Migrate teleport-db-1 volume (Option A)
4. **After verification**: Cleanup orphaned volumes

## Risks and Mitigation

**Risk**: Volume replication consumes additional disk space
- **Mitigation**: Monitor disk usage, current cluster has sufficient capacity

**Risk**: Replica creation may impact I/O performance during sync
- **Mitigation**: Longhorn throttles rebuild, minimal impact expected

**Risk**: Teleport database downtime during migration
- **Mitigation**: Option A provides minimal downtime, Option B has backup/restore path

## Success Criteria

- All storage classes configured with 3 replicas
- All active volumes have 3 replicas with `best-effort` data locality
- No orphaned/detached volumes remaining
- Volume health status shows `healthy` for all volumes
- No service interruptions for applications
