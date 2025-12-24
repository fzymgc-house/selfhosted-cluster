# Windmill S3 Storage Configuration

Guide for configuring Cloudflare R2 S3-compatible storage for Windmill workflows.

## Overview

Windmill supports S3-compatible object storage for:
- **Workflow artifacts**: Large files, inputs/outputs
- **Data storage**: Persistent workflow data
- **File operations**: S3 file picker in scripts

## Storage Architecture

Windmill uses **workspace-level S3 resources** configured through the UI, not Helm chart configuration. This is different from Argo Workflows which uses instance-level S3 for all artifacts.

## Configuration Steps

### 1. Prepare Cloudflare R2 Credentials

Create a Cloudflare R2 bucket and API token for Windmill:

**Step 1: Create R2 Bucket**
1. Login to Cloudflare Dashboard
2. Navigate to **R2** → **Create bucket**
3. Create bucket: `windmill-terraform-artifacts`
4. Note the bucket endpoint (e.g., `https://<account-id>.r2.cloudflarestorage.com`)

**Step 2: Generate R2 API Token**
1. Go to **R2** → **Manage R2 API Tokens**
2. Create API Token with:
   - **Permissions**: Read & Write
   - **Bucket**: `windmill-terraform-artifacts`
3. Note the Access Key ID and Secret Access Key

**Step 3: Store in Vault**
```bash
vault kv put secret/fzymgc-house/cluster/windmill \
  s3_access_key="<r2-access-key-id>" \
  s3_secret_key="<r2-secret-access-key>" \
  s3_bucket="<shared-bucket-name>" \
  s3_bucket_prefix="windmill/terraform-gitops" \
  s3_endpoint="https://<account-id>.r2.cloudflarestorage.com"
```

**Note**: The `s3_bucket_prefix` allows sharing a bucket with other services by organizing objects under a specific path prefix (e.g., `windmill/terraform-gitops/terraform/vault/terraform.tfstate`).

### 2. Create S3 Resource in Windmill

After the `terraform-gitops` workspace is created:

1. Login to Windmill at https://windmill.fzymgc.house
2. Navigate to the `terraform-gitops` workspace
3. Go to **Resources** → **Add a resource**
4. Select **S3/R2** type
5. Configure with Cloudflare R2 credentials:

```json
{
  "endpoint": "<account-id>.r2.cloudflarestorage.com",
  "region": "auto",
  "useSSL": true,
  "bucket": "windmill-terraform-artifacts",
  "accessKey": "<from-vault>",
  "secretKey": "<from-vault>",
  "pathStyle": false
}
```

**Note**: Cloudflare R2 uses `region: "auto"` instead of a specific region.

6. Save as resource: `f/resources/s3`

### 3. Configure Workspace Default Storage

1. Go to **Workspace Settings** → **S3 Storage**
2. Select the `f/resources/s3` resource
3. Click **Save**

This enables:
- S3 file picker in script parameters
- Automatic artifact storage for large outputs
- File preview and download in UI
- Data lineage tracking

## Using S3 in Workflows

### In Scripts

S3 resources can be used in Windmill scripts:

```typescript
// TypeScript example
import * as wmill from "windmill-client"

export async function main() {
  // S3 resource is automatically available
  const s3 = wmill.getResource("f/resources/s3")

  // Upload terraform plan output
  await wmill.writeS3File(
    s3,
    "terraform/vault/plans/plan-abc123.json",
    planOutput
  )

  return { planUrl: "..." }
}
```

### In Flows

Flows can reference S3 files in step inputs/outputs:

```yaml
# Flow step example
steps:
  - id: terraform-plan
    type: script
    path: terraform/plan
    result: s3://terraform/vault/plans/${flow.id}.json
```

## Storage Organization

Recommended R2 bucket structure with prefix for shared bucket:

```
<shared-bucket-name>/
└── windmill/
    └── terraform-gitops/           # s3_bucket_prefix
        ├── terraform/
        │   ├── vault/
        │   │   └── terraform.tfstate
        │   ├── grafana/
        │   │   └── terraform.tfstate
        │   └── authentik/
        │       └── terraform.tfstate
        └── workflows/
            └── artifacts/          # General workflow artifacts
```

The prefix `windmill/terraform-gitops` allows this workspace to coexist with other services in the same bucket.

## Verification

Test S3 configuration:

1. Create a test script in Windmill
2. Use S3 file picker to select/upload a file
3. Verify file appears in Cloudflare R2 bucket
4. Check Windmill logs for any S3 errors

```bash
# Check Windmill worker logs
kubectl --context fzymgc-house logs -n windmill -l app.kubernetes.io/name=windmill-workers --tail=50
```

## Troubleshooting

### S3 Connection Issues

```bash
# Check if S3 credentials are accessible
kubectl --context fzymgc-house exec -n windmill deployment/windmill-app -- \
  env | grep AWS
```

### Bucket Access Errors

Ensure Cloudflare R2 credentials have:
- Read/Write permissions on the R2 API token
- Bucket exists in Cloudflare R2
- Endpoint is correct (no https:// prefix in resource config)
- Region is set to `auto` (required for R2)

## Enterprise Features

**Note**: The following S3 features require Windmill Enterprise license:
- Distributed dependency caching
- Large log storage (>500KB logs)
- Multi-region replication

For this migration, we're using the **workspace-level S3 resources** which are available in the Community Edition.

## Migration from Argo Workflows

Key differences:
- **Argo**: Instance-level S3 configured via Helm chart
- **Windmill**: Workspace-level S3 configured via UI

Workflows will need to explicitly use S3 resources rather than automatic artifact storage.

## References

- Windmill S3 Documentation: https://www.windmill.dev/docs/core_concepts/object_storage_in_windmill
- Cloudflare R2 Documentation: https://developers.cloudflare.com/r2/
- Cloudflare R2 S3 API Compatibility: https://developers.cloudflare.com/r2/api/s3/api/
