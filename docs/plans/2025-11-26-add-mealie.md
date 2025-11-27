# Mealie Recipe Manager Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy Mealie recipe manager to the Kubernetes cluster with PostgreSQL backend, Vault-managed secrets, and HTTPS ingress via Traefik.

**Architecture:** Mealie will run as a Deployment in its own namespace, using CloudNativePG for PostgreSQL database, ExternalSecrets to sync credentials from Vault, Longhorn for persistent storage, and Traefik IngressRoute for HTTPS access at mealie.fzymgc.house.

**Tech Stack:**
- Mealie v3.5.0 (ghcr.io/mealie-recipes/mealie)
- CloudNativePG for PostgreSQL
- HashiCorp Vault for secrets
- Traefik for ingress
- cert-manager for TLS

---

## Task 1: Create PostgreSQL Database Resources

**Files:**
- Create: `argocd/app-configs/cnpg/db-mealie.yaml`
- Create: `argocd/app-configs/cnpg/users-mealie.yaml`
- Modify: `argocd/app-configs/cnpg/kustomization.yaml:9-13`

**Step 1: Create database resource**

Create `argocd/app-configs/cnpg/db-mealie.yaml`:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: mealie
  namespace: postgres
spec:
  cluster:
    name: main
  ensure: present
  name: mealie
  owner: mealie
```

**Step 2: Create user credentials ExternalSecret**

Create `argocd/app-configs/cnpg/users-mealie.yaml`:

```yaml
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: main-mealie-credentials
  namespace: postgres
spec:
  refreshPolicy: Periodic
  refreshInterval: 5m
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: main-mealie-credentials
    creationPolicy: Owner
    deletionPolicy: Delete
    template:
      metadata:
        labels:
          cnpg.io/reload: "true"
      type: kubernetes.io/basic-auth
      data:
        username: "{{ .username }}"
        password: "{{ .password }}"
  data:
    - secretKey: username
      remoteRef:
        key: fzymgc-house/cluster/postgres/users/main-mealie
        property: username
    - secretKey: password
      remoteRef:
        key: fzymgc-house/cluster/postgres/users/main-mealie
        property: password
```

**Step 3: Update kustomization to include new resources**

In `argocd/app-configs/cnpg/kustomization.yaml`, add to resources list:

```yaml
  - db-mealie.yaml
  - users-mealie.yaml
```

**Step 4: Commit database configuration**

```bash
git add argocd/app-configs/cnpg/db-mealie.yaml argocd/app-configs/cnpg/users-mealie.yaml argocd/app-configs/cnpg/kustomization.yaml
git commit -m "feat(cnpg): add mealie database and user"
```

---

## Task 2: Create Vault Secrets via CLI

**Step 1: Generate strong password for database user**

```bash
DB_PASSWORD=$(openssl rand -base64 32)
echo "Generated password (save for verification): $DB_PASSWORD"
```

**Step 2: Store database credentials in Vault**

```bash
vault kv put secret/fzymgc-house/cluster/postgres/users/main-mealie \
  username=mealie \
  password="$DB_PASSWORD"
```

Expected: Success! Data written to: secret/data/fzymgc-house/cluster/postgres/users/main-mealie

**Step 3: Verify secret was stored**

```bash
vault kv get secret/fzymgc-house/cluster/postgres/users/main-mealie
```

Expected: Should show username=mealie and password (redacted)

**Step 4: Create application secrets in Vault**

```bash
vault kv put secret/fzymgc-house/cluster/mealie \
  base_url="https://mealie.fzymgc.house" \
  allow_signup="false"
```

Expected: Success! Data written to: secret/data/fzymgc-house/cluster/mealie

---

## Task 3: Create Mealie Namespace and Basic Resources

**Files:**
- Create: `argocd/app-configs/mealie/namespace.yaml`
- Create: `argocd/app-configs/mealie/kustomization.yaml`

**Step 1: Create namespace**

Create `argocd/app-configs/mealie/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: mealie
```

**Step 2: Create kustomization file**

Create `argocd/app-configs/mealie/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: mealie

resources:
  - namespace.yaml
  - secrets.yaml
  - deployment.yaml
  - service.yaml
  - certificate.yaml
  - ingress.yaml
```

**Step 3: Commit namespace configuration**

```bash
git add argocd/app-configs/mealie/namespace.yaml argocd/app-configs/mealie/kustomization.yaml
git commit -m "feat(mealie): add namespace and kustomization"
```

---

## Task 4: Create ExternalSecrets for Mealie

**Files:**
- Create: `argocd/app-configs/mealie/secrets.yaml`

**Step 1: Create ExternalSecret for database and app secrets**

Create `argocd/app-configs/mealie/secrets.yaml`:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: mealie-db-secrets
  namespace: mealie
spec:
  refreshPolicy: Periodic
  refreshInterval: 5m
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: mealie-db-secrets
    creationPolicy: Owner
    deletionPolicy: Delete
    template:
      type: Opaque
      data:
        db-url: "postgres://{{ .postgres_user }}:{{ .postgres_password }}@main-rw.postgres.svc.cluster.local:5432/mealie"
  data:
    - secretKey: postgres_user
      remoteRef:
        key: fzymgc-house/cluster/postgres/users/main-mealie
        property: username
    - secretKey: postgres_password
      remoteRef:
        key: fzymgc-house/cluster/postgres/users/main-mealie
        property: password
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: mealie-app-secrets
  namespace: mealie
spec:
  refreshPolicy: Periodic
  refreshInterval: 5m
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: mealie-app-secrets
    creationPolicy: Owner
    deletionPolicy: Delete
    template:
      type: Opaque
      data:
        base-url: "{{ .base_url }}"
        allow-signup: "{{ .allow_signup }}"
  data:
    - secretKey: base_url
      remoteRef:
        key: fzymgc-house/cluster/mealie
        property: base_url
    - secretKey: allow_signup
      remoteRef:
        key: fzymgc-house/cluster/mealie
        property: allow_signup
```

**Step 2: Commit secrets configuration**

```bash
git add argocd/app-configs/mealie/secrets.yaml
git commit -m "feat(mealie): add ExternalSecrets for database and app config"
```

---

## Task 5: Create Mealie Deployment and Service

**Files:**
- Create: `argocd/app-configs/mealie/deployment.yaml`
- Create: `argocd/app-configs/mealie/service.yaml`

**Step 1: Create deployment manifest**

Create `argocd/app-configs/mealie/deployment.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mealie-data
  namespace: mealie
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mealie
  namespace: mealie
  labels:
    app.kubernetes.io/name: mealie
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app.kubernetes.io/name: mealie
  template:
    metadata:
      labels:
        app.kubernetes.io/name: mealie
    spec:
      containers:
        - name: mealie
          image: ghcr.io/mealie-recipes/mealie:v3.5.0
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 9000
              name: http
              protocol: TCP
          env:
            - name: DB_ENGINE
              value: "postgres"
            - name: POSTGRES_URL_OVERRIDE
              valueFrom:
                secretKeyRef:
                  name: mealie-db-secrets
                  key: db-url
            - name: BASE_URL
              valueFrom:
                secretKeyRef:
                  name: mealie-app-secrets
                  key: base-url
            - name: ALLOW_SIGNUP
              valueFrom:
                secretKeyRef:
                  name: mealie-app-secrets
                  key: allow-signup
            - name: TZ
              value: "America/Los_Angeles"
            - name: MAX_WORKERS
              value: "1"
            - name: WEB_CONCURRENCY
              value: "1"
          volumeMounts:
            - name: mealie-data
              mountPath: /app/data
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "1000Mi"
              cpu: "1000m"
          livenessProbe:
            httpGet:
              path: /api/app/about
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /api/app/about
              port: http
            initialDelaySeconds: 15
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
      volumes:
        - name: mealie-data
          persistentVolumeClaim:
            claimName: mealie-data
      restartPolicy: Always
```

**Step 2: Create service manifest**

Create `argocd/app-configs/mealie/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mealie
  namespace: mealie
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: mealie
  ports:
    - protocol: TCP
      port: 9000
      targetPort: http
      name: http
```

**Step 3: Commit deployment and service**

```bash
git add argocd/app-configs/mealie/deployment.yaml argocd/app-configs/mealie/service.yaml
git commit -m "feat(mealie): add deployment and service manifests"
```

---

## Task 6: Create Certificate and Ingress

**Files:**
- Create: `argocd/app-configs/mealie/certificate.yaml`
- Create: `argocd/app-configs/mealie/ingress.yaml`

**Step 1: Create certificate resource**

Create `argocd/app-configs/mealie/certificate.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: mealie-tls
  namespace: mealie
spec:
  secretName: mealie-tls
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  dnsNames:
    - mealie.fzymgc.house
    - mealie.k8s.fzymgc.house
    - mealie.mealie.svc.cluster.local
    - mealie.mealie.svc
    - mealie
  usages:
    - server auth
```

**Step 2: Create Traefik IngressRoute**

Create `argocd/app-configs/mealie/ingress.yaml`:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: mealie
  namespace: mealie
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`mealie.fzymgc.house`)
      kind: Rule
      services:
        - name: mealie
          port: 9000
    - match: Host(`mealie.k8s.fzymgc.house`)
      kind: Rule
      services:
        - name: mealie
          port: 9000
  tls:
    secretName: mealie-tls
```

**Step 3: Commit certificate and ingress**

```bash
git add argocd/app-configs/mealie/certificate.yaml argocd/app-configs/mealie/ingress.yaml
git commit -m "feat(mealie): add certificate and Traefik ingress"
```

---

## Task 7: Deploy and Verify

**Step 1: Apply CNPG database configuration**

```bash
kubectl --context fzymgc-house apply -k argocd/app-configs/cnpg
```

Expected:
- database.postgresql.cnpg.io/mealie created
- externalsecret.external-secrets.io/main-mealie-credentials created

**Step 2: Verify database user secret was synced**

```bash
kubectl --context fzymgc-house get secret -n postgres main-mealie-credentials
```

Expected: Secret exists with type kubernetes.io/basic-auth

**Step 3: Apply Mealie application**

```bash
kubectl --context fzymgc-house apply -k argocd/app-configs/mealie
```

Expected:
- namespace/mealie created
- externalsecret.external-secrets.io/mealie-db-secrets created
- externalsecret.external-secrets.io/mealie-app-secrets created
- persistentvolumeclaim/mealie-data created
- deployment.apps/mealie created
- service/mealie created
- certificate.cert-manager.io/mealie-tls created
- ingressroute.traefik.io/mealie created

**Step 4: Verify ExternalSecrets synced successfully**

```bash
kubectl --context fzymgc-house get externalsecret -n mealie
```

Expected: Both externalsecrets show SecretSynced=True

**Step 5: Watch deployment rollout**

```bash
kubectl --context fzymgc-house rollout status deployment/mealie -n mealie
```

Expected: deployment "mealie" successfully rolled out

**Step 6: Check pod status**

```bash
kubectl --context fzymgc-house get pods -n mealie
```

Expected: mealie pod in Running state with 1/1 ready

**Step 7: Verify certificate was issued**

```bash
kubectl --context fzymgc-house get certificate -n mealie mealie-tls
```

Expected: READY=True

**Step 8: Check application logs**

```bash
kubectl --context fzymgc-house logs -n mealie -l app.kubernetes.io/name=mealie --tail=50
```

Expected: No error messages, application started successfully

**Step 9: Test HTTPS access**

```bash
curl -I https://mealie.fzymgc.house
```

Expected: HTTP/2 200 response

**Step 10: Commit verification notes**

```bash
git add -A
git commit -m "docs(mealie): deployment verified and operational"
```

---

## Task 8: Optional - Create Vault Policy for Future GitOps

**Files:**
- Create: `tf/vault/policy-mealie.tf`
- Create: `tf/vault/k8s-mealie.tf`
- Modify: `tf/vault/versions.tf` (if needed)

**Step 1: Create Vault policy for Mealie**

Create `tf/vault/policy-mealie.tf`:

```hcl
data "vault_policy_document" "mealie" {
  rule {
    path         = "secret/data/fzymgc-house/cluster/mealie"
    capabilities = ["read", "list"]
    description  = "Allow Mealie to read app configuration"
  }

  rule {
    path         = "secret/data/fzymgc-house/cluster/postgres/users/main-mealie"
    capabilities = ["read"]
    description  = "Allow Mealie to read database credentials"
  }
}

resource "vault_policy" "mealie" {
  name   = "mealie"
  policy = data.vault_policy_document.mealie.hcl
}
```

**Step 2: Create Kubernetes auth backend role**

Create `tf/vault/k8s-mealie.tf`:

```hcl
resource "vault_kubernetes_auth_backend_role" "mealie" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "mealie"
  bound_service_account_names      = ["default"]
  bound_service_account_namespaces = ["mealie"]
  token_ttl                        = 3600
  token_policies                   = ["default", vault_policy.mealie.name]
}
```

**Step 3: Initialize and plan Terraform changes**

```bash
cd tf/vault
terraform init
terraform plan -out=tfplan
```

Expected: Plan shows 2 resources to add (policy and k8s auth role)

**Step 4: Apply Terraform changes**

```bash
terraform apply tfplan
```

Expected: Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

**Step 5: Commit Terraform configuration**

```bash
cd ../..
git add tf/vault/policy-mealie.tf tf/vault/k8s-mealie.tf
git commit -m "feat(vault): add Mealie policy and Kubernetes auth role"
```

---

## Post-Deployment Configuration

After deployment, access Mealie at `https://mealie.fzymgc.house` to:

1. Create initial admin user (since ALLOW_SIGNUP is false, only first user can self-register)
2. Configure any additional settings via the web UI
3. Import recipes or set up integration with external services

## Verification Checklist

- [ ] PostgreSQL database `mealie` exists in CNPG cluster
- [ ] Database credentials stored in Vault
- [ ] ExternalSecrets syncing successfully
- [ ] Deployment running with 1/1 pods ready
- [ ] PVC bound and mounted
- [ ] Certificate issued by vault-issuer
- [ ] HTTPS accessible via Traefik at mealie.fzymgc.house
- [ ] Application logs show no errors
- [ ] Initial user can be created via web UI

## Rollback Plan

If issues occur:

```bash
# Remove application
kubectl --context fzymgc-house delete -k argocd/app-configs/mealie

# Remove database (WARNING: destroys data)
kubectl --context fzymgc-house delete database mealie -n postgres
kubectl --context fzymgc-house delete externalsecret main-mealie-credentials -n postgres

# Clean up Vault secrets
vault kv delete secret/fzymgc-house/cluster/mealie
vault kv delete secret/fzymgc-house/cluster/postgres/users/main-mealie
```

## References

- [Mealie Documentation](https://docs.mealie.io/)
- [Mealie GitHub](https://github.com/mealie-recipes/mealie)
- [Backend Configuration](https://docs.mealie.io/documentation/getting-started/installation/backend-config/)
- [PostgreSQL Setup](https://docs.mealie.io/documentation/getting-started/installation/postgres/)
