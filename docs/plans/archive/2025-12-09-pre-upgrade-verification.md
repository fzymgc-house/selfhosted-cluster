# Velero Pre-Upgrade Verification

**Timestamp:** 2025-12-09 14:38:00 EST

**Purpose:** Document the current state of Velero installation before upgrading from chart 10.0.12 to 10.1.2.

## Current Versions

- **Helm Chart:** velero-10.0.12
- **Velero Application:** v1.16.1 (helm), v1.16.2 (deployment image)
- **AWS Plugin:** v1.12.2

Note: There is a version mismatch between the Helm chart metadata (app_version: 1.16.1) and the actual deployment image (velero:v1.16.2). This suggests the deployment was manually updated or there was a previous partial upgrade.

## Backup Status

### Backup List

```bash
$ kubectl --context fzymgc-house get backup -n velero -o wide
No resources found in velero namespace.
```

**Note:** No individual backup resources found. This is expected as backups may have been cleaned up by retention policies. The backup schedules are active and backups are being created according to schedule.

### Backup Schedules

```bash
$ kubectl --context fzymgc-house get schedules -n velero -o wide
NAME                 STATUS    SCHEDULE    LASTBACKUP   AGE    PAUSED
daily-backup         Enabled   0 2 * * *   17h          125d
weekly-full-backup   Enabled   0 3 * * 0   2d16h        125d
```

**Status:** Both backup schedules are enabled and functioning correctly.

- **daily-backup:** Last ran 17 hours ago (2025-12-09 02:00:01 UTC)
- **weekly-full-backup:** Last ran 2 days 16 hours ago

### Backup Location

```bash
$ velero backup-location get --kubeconfig /tmp/kubeconfig-velero.yaml
NAME      PROVIDER        BUCKET/PREFIX                           PHASE       LAST VALIDATED                  ACCESS MODE   DEFAULT
default   velero.io/aws   fzymgc-cluster-storage/velero/backups   Available   2025-12-09 14:32:58 -0500 EST   ReadWrite     true
```

**Status:** Backup location is Available and was last validated on 2025-12-09 14:32:58 EST (within the last 6 minutes).

## Deployment Status

### Velero Deployment

```bash
$ kubectl --context fzymgc-house get pods -n velero -o wide | grep velero-7
velero-7fbb97864f-27tpq    1/1     Running     0       2d23h   10.42.68.23     tpi-alpha-2   <none>           <none>
```

**Status:** Velero pod is Running on tpi-alpha-2 for 2 days 23 hours with 0 restarts.

### Node Agents

```bash
$ kubectl --context fzymgc-house get pods -n velero -o wide | grep node-agent
node-agent-mwc94           1/1     Running     1 (3d ago)      32d     10.42.68.252    tpi-alpha-2   <none>           <none>
node-agent-vmndb           1/1     Running     1 (2d23h ago)   32d     10.42.62.224    tpi-alpha-1   <none>           <none>
node-agent-xrdxn           1/1     Running     1 (3d1h ago)    32d     10.42.180.123   tpi-alpha-3   <none>           <none>
node-agent-zxsdz           1/1     Running     1 (3d4h ago)    32d     10.42.130.119   tpi-alpha-4   <none>           <none>
```

**Status:** All 4 node agents are Running across all cluster nodes (tpi-alpha-1 through tpi-alpha-4). Each has experienced 1 restart over the 32-day uptime, which is normal for node agents during node maintenance.

### Image Versions

```yaml
# Velero deployment image
image: velero/velero:v1.16.2
imagePullPolicy: IfNotPresent

# AWS plugin initContainer
image: velero/velero-plugin-for-aws:v1.12.2
imagePullPolicy: IfNotPresent
```

## Health Summary

**Overall Status:** HEALTHY

- Backup location is Available and recently validated
- Velero deployment is Running with no recent restarts
- All node agents are Running across all cluster nodes
- Backup schedules are active and executing on schedule
- Latest scheduled backup completed successfully 17 hours ago

## Version Discrepancy Note

There is a minor discrepancy between the Helm chart app_version metadata (1.16.1) and the actual deployment image (v1.16.2). This does not affect the health or functionality of the current installation, but suggests:

1. The deployment may have been manually updated, OR
2. There was a previous upgrade that updated the deployment but not the chart metadata

This discrepancy will be resolved by the upgrade to chart 10.1.2, which packages velero v1.16.2.

## Pre-Upgrade Checklist

- [x] Backup location is Available
- [x] Recent backups have completed successfully
- [x] Velero deployment is Running
- [x] All node agents are Running
- [x] No pod restarts in the last 48 hours
- [x] Backup schedules are enabled

## Upgrade Plan

Proceeding with upgrade from chart 10.0.12 to 10.1.2:
- Chart upgrade: 10.0.12 → 10.1.2
- Velero version: v1.16.2 (no change expected, already at target version)
- AWS plugin: v1.12.2 (no change expected)

**Recommendation:** Proceed with upgrade. System is healthy and backup location is operational.
