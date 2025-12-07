# Windmill S3 Storage Configuration

Guide for configuring Storj S3 storage for Windmill workflows.

## Overview

Windmill supports S3-compatible object storage for:
- **Workflow artifacts**: Large files, inputs/outputs
- **Data storage**: Persistent workflow data
- **File operations**: S3 file picker in scripts

## Storage Architecture

Windmill uses **workspace-level S3 resources** configured through the UI, not Helm chart configuration. This is different from Argo Workflows which uses instance-level S3 for all artifacts.

## Configuration Steps

### 1. Prepare Storj Credentials

The same Storj credentials used by Argo Workflows can be reused, or create a separate bucket:

**Option A: Reuse Argo Workflows credentials**
```bash
# Credentials already exist in Vault
vault kv get secret/fzymgc-house/cluster/argo-workflow

# Keys:
# - artifact_storage_access_key
# - artifact_storage_secret_key
# - Bucket: argo-workflows
# - Endpoint: https://gateway.storjshare.io
```

**Option B: Create separate Windmill bucket (Recommended)**
```bash
# 1. Create new bucket in Storj dashboard: windmill-storage
# 2. Generate access credentials
# 3. Store in Vault:
vault kv put secret/fzymgc-house/cluster/windmill \
  s3_access_key="<access-key>" \
  s3_secret_key="<secret-key>" \
  s3_bucket="windmill-storage" \
  s3_endpoint="https://gateway.storjshare.io"
```

### 2. Create S3 Resource in Windmill

After the `terraform-gitops` workspace is created:

1. Login to Windmill at https://windmill.fzymgc.house
2. Navigate to the `terraform-gitops` workspace
3. Go to **Resources** → **Add a resource**
4. Select **S3/R2** type
5. Configure with Storj credentials:

```json
{
  "endpoint": "gateway.storjshare.io",
  "region": "us-east-1",
  "useSSL": true,
  "bucket": "windmill-storage",
  "accessKey": "<from-vault>",
  "secretKey": "<from-vault>",
  "pathStyle": false
}
```

6. Save as resource: `u/admin/terraform_storage`

### 3. Configure Workspace Default Storage

1. Go to **Workspace Settings** → **S3 Storage**
2. Select the `u/admin/terraform_storage` resource
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
  const s3 = wmill.getResource("u/admin/terraform_storage")

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

Recommended S3 bucket structure:

```
windmill-storage/
├── terraform/
│   ├── vault/
│   │   ├── plans/        # Terraform plan outputs
│   │   └── logs/         # Execution logs
│   ├── grafana/
│   │   ├── plans/
│   │   └── logs/
│   └── authentik/
│       ├── plans/
│       └── logs/
└── workflows/
    └── artifacts/        # General workflow artifacts
```

## Verification

Test S3 configuration:

1. Create a test script in Windmill
2. Use S3 file picker to select/upload a file
3. Verify file appears in Storj bucket
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

Ensure Storj credentials have:
- Read/Write access to bucket
- Bucket exists in Storj
- Endpoint is correct (no https:// prefix in resource config)

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
- Storj Gateway Documentation: https://docs.storj.io/dcs/api-reference/s3-compatible-gateway
