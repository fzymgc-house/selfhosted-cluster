# wal2json Extension Image Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and deploy a wal2json PostgreSQL extension container image for CNPG ImageVolume, then upgrade Teleport's PostgreSQL to 18 with the extension enabled.

**Architecture:** Multi-stage Dockerfile extracts wal2json from PGDG packages into a minimal scratch image. GitHub Actions builds multi-arch images on push. CNPG mounts the extension via ImageVolume into PostgreSQL 18 pods.

**Tech Stack:** Docker, GitHub Actions, CNPG, PostgreSQL 18, Kubernetes

---

### Task 1: Create wal2json Dockerfile

**Files:**
- Create: `containers/wal2json/Dockerfile`

**Step 1: Create the containers directory**

```bash
mkdir -p containers/wal2json
```

**Step 2: Create the Dockerfile**

Create `containers/wal2json/Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1
# wal2json extension image for CloudNativePG ImageVolume
# https://github.com/eulerto/wal2json

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
# CNPG expects: /lib/*.so and /share/extension/*
FROM scratch

COPY --from=builder /usr/lib/postgresql/18/lib/wal2json.so /lib/
COPY --from=builder /usr/share/postgresql/18/extension/wal2json* /share/extension/
```

**Step 3: Commit**

```bash
git add containers/wal2json/Dockerfile
git commit -m "feat(wal2json): Add Dockerfile for PostgreSQL 18 extension image"
```

---

### Task 2: Add wal2json LICENSE file

**Files:**
- Create: `containers/wal2json/LICENSE`

**Step 1: Create the LICENSE file**

wal2json is BSD-3-Clause licensed. Create `containers/wal2json/LICENSE`:

```
BSD 3-Clause License

Copyright (c) 2013-2024, Euler Taveira de Oliveira
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

**Step 2: Commit**

```bash
git add containers/wal2json/LICENSE
git commit -m "feat(wal2json): Add BSD-3-Clause LICENSE"
```

---

### Task 3: Create GitHub Actions workflow

**Files:**
- Create: `.github/workflows/build-wal2json.yaml`

**Step 1: Create the workflow file**

Create `.github/workflows/build-wal2json.yaml`:

```yaml
name: Build wal2json Extension

on:
  push:
    branches: [main]
    paths:
      - 'containers/wal2json/**'
      - '.github/workflows/build-wal2json.yaml'
  workflow_dispatch:

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository_owner }}/wal2json

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=raw,value=2.6-pg18-trixie
            type=raw,value=latest

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: containers/wal2json
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

**Step 2: Commit**

```bash
git add .github/workflows/build-wal2json.yaml
git commit -m "feat(wal2json): Add GitHub Actions workflow for multi-arch build"
```

---

### Task 4: Push branch and create PR

**Files:**
- None (git operations only)

**Step 1: Push the branch**

```bash
git push -u origin feat/wal2json-extension
```

**Step 2: Create PR**

```bash
gh pr create --title "feat: Add wal2json extension image for CNPG ImageVolume" --body "$(cat <<'EOF'
## Summary

- Adds Dockerfile for wal2json PostgreSQL extension
- GitHub Actions workflow builds multi-arch images (amd64 + arm64)
- Images pushed to `ghcr.io/fzymgc-house/wal2json`

## Purpose

Enables Teleport PostgreSQL backend by providing wal2json extension via CNPG ImageVolume feature (requires k8s 1.33+, PG 18+).

## Image Details

- **Base:** Debian Trixie (matches CNPG PG18 images)
- **Tag:** `2.6-pg18-trixie`
- **Size:** ~50KB (scratch image with only extension files)

## Testing

After merge, workflow will build and push image. Then update Teleport's postgres-cluster.yaml to use PG18 with extension.

## Related

- Design: docs/plans/2025-12-05-wal2json-extension-image-design.md
- Issue: #97

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 3: Wait for PR merge and workflow completion**

After PR is merged, verify the image was built:

```bash
gh run list --workflow=build-wal2json.yaml --limit 1
```

Expected: Workflow run completed successfully.

---

### Task 5: Update Teleport PostgreSQL cluster to PG18 with wal2json

**Files:**
- Modify: `argocd/app-configs/teleport/postgres-cluster.yaml`

**Step 1: Update the cluster manifest**

Replace contents of `argocd/app-configs/teleport/postgres-cluster.yaml`:

```yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: teleport-db
  namespace: teleport
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  instances: 1

  # PostgreSQL 18 minimal image (required for ImageVolume extensions)
  imageName: ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie

  postgresql:
    parameters:
      wal_level: logical
      max_replication_slots: "10"

    # ImageVolume extension for wal2json
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

  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m
```

**Step 2: Commit**

```bash
git add argocd/app-configs/teleport/postgres-cluster.yaml
git commit -m "feat(teleport): Upgrade to PostgreSQL 18 with wal2json ImageVolume extension"
```

**Step 3: Push and create PR**

```bash
git push
gh pr create --title "feat(teleport): Upgrade PostgreSQL to 18 with wal2json extension" --body "$(cat <<'EOF'
## Summary

- Upgrades Teleport PostgreSQL from 17.5 to 18-minimal-trixie
- Adds wal2json extension via CNPG ImageVolume feature

## Breaking Change

This is a PostgreSQL major version upgrade. The existing teleport-db cluster will be recreated, losing any existing data.

## Changes

| Setting | Before | After |
|---------|--------|-------|
| PostgreSQL | 17.5 | 18-minimal-trixie |
| wal2json | Not available | Via ImageVolume |

## Verification

After sync, verify extension is available:

```bash
kubectl --context fzymgc-house exec -it -n teleport teleport-db-1 -- psql -U teleport -c "SELECT * FROM pg_available_extensions WHERE name = 'wal2json';"
```

## Related

- Issue: #97
- Depends on: wal2json image PR

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

### Task 6: Verify wal2json extension is available

**Files:**
- None (verification only)

**Step 1: Wait for ArgoCD sync**

```bash
kubectl --context fzymgc-house get cluster teleport-db -n teleport -w
```

Expected: Cluster becomes "Cluster in healthy state"

**Step 2: Verify extension is available**

```bash
kubectl --context fzymgc-house exec -it -n teleport teleport-db-1 -- psql -U teleport -d teleport -c "SELECT * FROM pg_available_extensions WHERE name = 'wal2json';"
```

Expected output:
```
  name   | default_version | installed_version |          comment
---------+-----------------+-------------------+---------------------------
 wal2json| 2.6             |                   | JSON output plugin...
```

**Step 3: Verify ImageVolume mount**

```bash
kubectl --context fzymgc-house exec -it -n teleport teleport-db-1 -- ls -la /extensions/wal2json/
```

Expected: Shows `lib/` and `share/` directories with wal2json files.

---

### Task 7: Close Issue #97

**Files:**
- None (GitHub operations only)

**Step 1: Update issue with completion status**

```bash
gh issue comment 97 --body "$(cat <<'EOF'
## Completed

- ✅ Kubernetes upgraded to 1.34.2 (PR #104)
- ✅ wal2json extension image built and pushed to ghcr.io/fzymgc-house/wal2json
- ✅ Teleport PostgreSQL upgraded to 18 with ImageVolume extension

The wal2json extension is now available in the Teleport PostgreSQL cluster. Teleport can now use PostgreSQL as its backend with logical replication support.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 2: Close the issue**

```bash
gh issue close 97
```
