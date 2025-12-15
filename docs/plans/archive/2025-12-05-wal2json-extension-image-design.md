# wal2json Extension Image Design

**Date:** 2025-12-05
**Status:** Approved
**Issue:** #97

## Goal

Build a wal2json extension container image for PostgreSQL 18 to enable Teleport's PostgreSQL backend using CNPG's ImageVolume feature.

## Background

Teleport requires the `wal2json` logical decoding plugin for PostgreSQL backend support. CNPG 1.27+ supports dynamic extension loading via Kubernetes ImageVolume (requires k8s 1.33+, PG 18+). Rather than building custom PostgreSQL images, we can mount extensions as read-only volumes.

## Requirements

| Component | Current | Required | Status |
|-----------|---------|----------|--------|
| CloudNativePG | 1.27.0 | 1.27+ | ✅ |
| Kubernetes | 1.34.2 | 1.33+ | ✅ |
| PostgreSQL | 17.5 | 18+ | Upgrade needed |
| wal2json image | N/A | Build | Build needed |

## Design

### Directory Structure

```
containers/
└── wal2json/
    ├── Dockerfile
    └── LICENSE
.github/
└── workflows/
    └── build-wal2json.yaml
```

### Image Details

- **Registry:** `ghcr.io/fzymgc-house/wal2json`
- **Tag format:** `<version>-pg18-trixie` (e.g., `2.6-pg18-trixie`)
- **Architectures:** `linux/amd64`, `linux/arm64`
- **Base:** Debian Trixie (matching CNPG PostgreSQL 18 images)

### CNPG ImageVolume Layout

```
/share/extension/wal2json.control
/share/extension/wal2json--*.sql
/lib/wal2json.so
```

### Dockerfile

Multi-stage build using PGDG apt repository:

```dockerfile
# Stage 1: Install wal2json from PGDG
FROM debian:trixie-slim AS builder

ARG PG_MAJOR=18

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
      gpg --dearmor -o /usr/share/keyrings/pgdg.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt trixie-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      postgresql-${PG_MAJOR}-wal2json && \
    rm -rf /var/lib/apt/lists/*

# Stage 2: Create minimal extension image
FROM scratch

COPY --from=builder /usr/lib/postgresql/18/lib/wal2json.so /lib/
COPY --from=builder /usr/share/postgresql/18/extension/wal2json* /share/extension/
```

### GitHub Actions Workflow

Triggers on push to `containers/wal2json/` or workflow file. Uses QEMU for multi-arch builds, pushes to GHCR with `GITHUB_TOKEN`.

### Teleport Cluster Configuration

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: teleport-db
  namespace: teleport
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie

  postgresql:
    parameters:
      wal_level: logical
      max_replication_slots: "10"
    extensions:
      - name: wal2json
        image:
          reference: ghcr.io/fzymgc-house/wal2json:2.6-pg18-trixie

  bootstrap:
    initdb:
      database: teleport
      owner: teleport
      secret:
        name: teleport-db-credentials
      postInitSQL:
        - ALTER ROLE teleport WITH REPLICATION;

  storage:
    size: 5Gi
    storageClass: postgres-storage
```

## Implementation Sequence

### Phase 1: Build Extension Image
1. Create `containers/wal2json/Dockerfile`
2. Add `containers/wal2json/LICENSE` (BSD-3-Clause)
3. Create `.github/workflows/build-wal2json.yaml`
4. Push to main → workflow builds and pushes image

### Phase 2: Upgrade Teleport PostgreSQL
1. Back up Teleport data (if critical state exists)
2. Delete existing `teleport-db` Cluster (PG 17 → 18 requires recreate)
3. Update `postgres-cluster.yaml` with PG 18 + wal2json extension
4. ArgoCD syncs new cluster
5. Verify: `SELECT * FROM pg_available_extensions WHERE name = 'wal2json';`

### Phase 3: Verify Teleport
1. Check Teleport can use PostgreSQL backend
2. Monitor logs for wal2json errors

## Risks

- **Database recreation:** PG 17 → 18 upgrade requires cluster recreation. Any existing Teleport state will be lost unless backed up.
- **wal2json compatibility:** Must match PostgreSQL major version and Debian release exactly.

## References

- [CNPG ImageVolume Extensions](https://cloudnative-pg.io/documentation/current/imagevolume_extensions/)
- [wal2json GitHub](https://github.com/eulerto/wal2json)
- [CNPG postgres-extensions-containers](https://github.com/cloudnative-pg/postgres-extensions-containers)
