# Teleport Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy self-hosted Teleport providing SSH and Kubernetes access with Authentik OIDC authentication.

**Architecture:** Teleport runs as a Helm-deployed cluster in `standalone` mode with PostgreSQL backend (CNPG), Vault-managed secrets via ExternalSecrets, and Authentik OIDC for authentication. Node agents are deployed via Ansible.

**Tech Stack:** Teleport Helm chart, CloudNativePG, HashiCorp Vault, Authentik, Terraform, Ansible

---

## Phase 1: Core Infrastructure

### Task 1.1: Create Teleport Namespace and Base Resources

**Files:**
- Create: `argocd/app-configs/teleport/kustomization.yaml`
- Create: `argocd/app-configs/teleport/namespace.yaml`

**Step 1: Create the directory structure**

```bash
mkdir -p argocd/app-configs/teleport
```

**Step 2: Create namespace.yaml**

```yaml
# argocd/app-configs/teleport/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: teleport
  labels:
    app.kubernetes.io/name: teleport
```

**Step 3: Create initial kustomization.yaml**

```yaml
# argocd/app-configs/teleport/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
```

**Step 4: Verify kustomize output**

```bash
kubectl --context fzymgc-house kustomize argocd/app-configs/teleport
```

**Step 5: Commit**

```bash
git add argocd/app-configs/teleport/
git commit -m "feat(teleport): Add namespace and kustomization base"
```

---

### Task 1.2: Create Vault Policy for Teleport

**Files:**
- Create: `tf/vault/policy-teleport.tf`

**Step 1: Create the Vault policy file**

```hcl
# tf/vault/policy-teleport.tf

resource "vault_policy" "teleport" {
  name   = "teleport"
  policy = <<EOT
# Read teleport secrets
path "secret/data/fzymgc-house/cluster/teleport/*" {
  capabilities = ["read"]
}

path "secret/metadata/fzymgc-house/cluster/teleport/*" {
  capabilities = ["list"]
}
EOT
}
```

**Step 2: Format and validate**

```bash
cd tf/vault
terraform fmt
terraform validate
```

**Step 3: Plan and apply**

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

**Step 4: Commit**

```bash
git add tf/vault/policy-teleport.tf
git commit -m "feat(vault): Add teleport policy for secret access"
```

---

### Task 1.3: Create Vault Kubernetes Auth Role for Teleport

**Files:**
- Create: `tf/vault/k8s-teleport.tf`

**Step 1: Create the Kubernetes auth role file**

```hcl
# tf/vault/k8s-teleport.tf

resource "vault_kubernetes_auth_backend_role" "teleport" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "teleport"
  bound_service_account_namespaces = ["teleport"]
  bound_service_account_names      = ["teleport"]
  audience                         = "https://kubernetes.default.svc.cluster.local"
  token_policies                   = ["default", "teleport"]
}
```

**Step 2: Format and validate**

```bash
cd tf/vault
terraform fmt
terraform validate
```

**Step 3: Plan and apply**

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

**Step 4: Commit**

```bash
git add tf/vault/k8s-teleport.tf
git commit -m "feat(vault): Add Kubernetes auth role for teleport service account"
```

---

### Task 1.4: Create PostgreSQL Cluster for Teleport

**Files:**
- Create: `argocd/app-configs/teleport/postgres-cluster.yaml`
- Modify: `argocd/app-configs/teleport/kustomization.yaml`

**Step 1: Create the CNPG cluster definition**

```yaml
# argocd/app-configs/teleport/postgres-cluster.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: teleport-db
  namespace: teleport
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:17.5-standard-bullseye

  primaryUpdateStrategy: unsupervised

  enableSuperuserAccess: false

  bootstrap:
    initdb:
      database: teleport_backend
      owner: teleport
      secret:
        name: teleport-db-credentials

  postgresql:
    parameters:
      wal_level: logical
      max_replication_slots: "10"

  storage:
    size: 5Gi
    storageClass: postgres-storage

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
```

**Step 2: Update kustomization.yaml**

```yaml
# argocd/app-configs/teleport/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - postgres-cluster.yaml
```

**Step 3: Verify kustomize output**

```bash
kubectl --context fzymgc-house kustomize argocd/app-configs/teleport
```

**Step 4: Commit**

```bash
git add argocd/app-configs/teleport/
git commit -m "feat(teleport): Add CNPG PostgreSQL cluster for backend storage"
```

---

### Task 1.5: Create ExternalSecret for PostgreSQL Credentials

**Files:**
- Create: `argocd/app-configs/teleport/db-secrets.yaml`
- Modify: `argocd/app-configs/teleport/kustomization.yaml`

**Step 1: Manually create the initial secret in Vault**

```bash
# Generate a random password
DB_PASSWORD=$(openssl rand -base64 24)

# Store in Vault
vault kv put secret/fzymgc-house/cluster/teleport/db \
  username=teleport \
  password="$DB_PASSWORD"
```

**Step 2: Create the ExternalSecret**

```yaml
# argocd/app-configs/teleport/db-secrets.yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: teleport-db-credentials
  namespace: teleport
spec:
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: teleport-db-credentials
    creationPolicy: Owner
    deletionPolicy: Delete
    template:
      type: kubernetes.io/basic-auth
      data:
        username: "{{ .username }}"
        password: "{{ .password }}"
  data:
    - secretKey: username
      remoteRef:
        key: fzymgc-house/cluster/teleport/db
        property: username
    - secretKey: password
      remoteRef:
        key: fzymgc-house/cluster/teleport/db
        property: password
```

**Step 3: Update kustomization.yaml**

```yaml
# argocd/app-configs/teleport/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - db-secrets.yaml
  - postgres-cluster.yaml
```

**Step 4: Verify kustomize output**

```bash
kubectl --context fzymgc-house kustomize argocd/app-configs/teleport
```

**Step 5: Commit**

```bash
git add argocd/app-configs/teleport/
git commit -m "feat(teleport): Add ExternalSecret for PostgreSQL credentials"
```

---

## Phase 2: Teleport Auth & Proxy Deployment

### Task 2.1: Create Teleport Service Account and RBAC

**Files:**
- Create: `argocd/app-configs/teleport/rbac.yaml`
- Modify: `argocd/app-configs/teleport/kustomization.yaml`

**Step 1: Create RBAC resources**

```yaml
# argocd/app-configs/teleport/rbac.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: teleport
  namespace: teleport
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: teleport-kubernetes-access
rules:
  # Allow Teleport to impersonate users and groups
  - apiGroups: [""]
    resources: ["users", "groups", "serviceaccounts"]
    verbs: ["impersonate"]
  # Allow Teleport to impersonate extras (e.g., for user extra info)
  - apiGroups: [""]
    resources: ["pods", "pods/exec", "pods/portforward", "pods/log"]
    verbs: ["*"]
  - apiGroups: [""]
    resources: ["namespaces", "services", "secrets", "configmaps", "persistentvolumeclaims"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch"]
  # SelfSubjectAccessReview for authorization checks
  - apiGroups: ["authorization.k8s.io"]
    resources: ["selfsubjectaccessreviews", "selfsubjectrulesreviews"]
    verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: teleport-kubernetes-access
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: teleport-kubernetes-access
subjects:
  - kind: ServiceAccount
    name: teleport
    namespace: teleport
```

**Step 2: Update kustomization.yaml**

```yaml
# argocd/app-configs/teleport/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - rbac.yaml
  - db-secrets.yaml
  - postgres-cluster.yaml
```

**Step 3: Verify kustomize output**

```bash
kubectl --context fzymgc-house kustomize argocd/app-configs/teleport
```

**Step 4: Commit**

```bash
git add argocd/app-configs/teleport/
git commit -m "feat(teleport): Add service account and RBAC for Kubernetes access"
```

---

### Task 2.2: Create ExternalSecret for Join Token

**Files:**
- Create: `argocd/app-configs/teleport/join-token-secret.yaml`
- Modify: `argocd/app-configs/teleport/kustomization.yaml`

**Step 1: Generate and store join token in Vault**

```bash
# Generate a secure join token
JOIN_TOKEN=$(openssl rand -hex 32)

# Store in Vault
vault kv put secret/fzymgc-house/cluster/teleport/join-token \
  token="$JOIN_TOKEN"
```

**Step 2: Create the ExternalSecret**

```yaml
# argocd/app-configs/teleport/join-token-secret.yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: teleport-join-token
  namespace: teleport
spec:
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: teleport-join-token
    creationPolicy: Owner
    deletionPolicy: Delete
    template:
      type: Opaque
      data:
        auth-token: "{{ .token }}"
  data:
    - secretKey: token
      remoteRef:
        key: fzymgc-house/cluster/teleport/join-token
        property: token
```

**Step 3: Update kustomization.yaml**

```yaml
# argocd/app-configs/teleport/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - rbac.yaml
  - db-secrets.yaml
  - join-token-secret.yaml
  - postgres-cluster.yaml
```

**Step 4: Commit**

```bash
git add argocd/app-configs/teleport/
git commit -m "feat(teleport): Add ExternalSecret for node join token"
```

---

### Task 2.3: Create Teleport Helm Values

**Files:**
- Create: `argocd/app-configs/teleport/values.yaml`

**Step 1: Create Helm values file**

```yaml
# argocd/app-configs/teleport/values.yaml
clusterName: teleport.fzymgc.house
kubeClusterName: fzymgc-house

# Use standalone mode with custom PostgreSQL backend
chartMode: standalone

# Disable built-in ACME, we'll use cert-manager
acme: false

# Authentication configuration - will be completed after Authentik setup
authentication:
  type: local
  secondFactors:
    - webauthn
    - otp

# Proxy listener mode for TLS routing
proxyListenerMode: multiplex

# Logging
log:
  level: INFO
  format: json

# Single replica for homelab
highAvailability:
  replicaCount: 1
  certManager:
    enabled: true
    issuerName: letsencrypt-prod
    issuerKind: ClusterIssuer

# Disable persistence since we use PostgreSQL
persistence:
  enabled: false

# Service account configuration
serviceAccount:
  create: false
  name: teleport

# Service configuration
service:
  type: LoadBalancer
  spec:
    loadBalancerIP: ""

# Custom teleport configuration for PostgreSQL backend
auth:
  teleportConfig:
    teleport:
      storage:
        type: postgresql
        conn_string: "postgresql://teleport@teleport-db-rw.teleport.svc.cluster.local:5432/teleport_backend?sslmode=verify-full&sslrootcert=/etc/teleport-db-certs/ca.crt"
    auth_service:
      tokens:
        - "node:/etc/teleport-join-token/auth-token"
      kubernetes_service:
        enabled: true
        listen_addr: 0.0.0.0:3026
        kube_cluster_name: fzymgc-house

# Extra volumes for database certs and join token
extraVolumes:
  - name: teleport-db-certs
    secret:
      secretName: teleport-db-ca
  - name: teleport-join-token
    secret:
      secretName: teleport-join-token

extraVolumeMounts:
  - name: teleport-db-certs
    mountPath: /etc/teleport-db-certs
    readOnly: true
  - name: teleport-join-token
    mountPath: /etc/teleport-join-token
    readOnly: true

# Resource limits
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    memory: 1Gi
```

**Step 2: Commit**

```bash
git add argocd/app-configs/teleport/values.yaml
git commit -m "feat(teleport): Add Helm values for teleport-cluster chart"
```

---

### Task 2.4: Create Certificate for Teleport

**Files:**
- Create: `argocd/app-configs/teleport/certificate.yaml`
- Modify: `argocd/app-configs/teleport/kustomization.yaml`

**Step 1: Create Certificate resource**

```yaml
# argocd/app-configs/teleport/certificate.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: teleport-public-tls
  namespace: teleport
spec:
  secretName: teleport-public-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: teleport.fzymgc.house
  dnsNames:
    - teleport.fzymgc.house
    - "*.teleport.fzymgc.house"
```

**Step 2: Update kustomization.yaml**

```yaml
# argocd/app-configs/teleport/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - rbac.yaml
  - db-secrets.yaml
  - join-token-secret.yaml
  - certificate.yaml
  - postgres-cluster.yaml
```

**Step 3: Commit**

```bash
git add argocd/app-configs/teleport/
git commit -m "feat(teleport): Add cert-manager Certificate for TLS"
```

---

### Task 2.5: Create ArgoCD Application for Teleport

**Files:**
- Create: `argocd/applications/teleport.yaml`

**Step 1: Create ArgoCD Application**

```yaml
# argocd/applications/teleport.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: teleport
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  sources:
    # Teleport Helm chart
    - repoURL: https://charts.releases.teleport.dev
      chart: teleport-cluster
      targetRevision: "17.0.3"
      helm:
        valueFiles:
          - $values/argocd/app-configs/teleport/values.yaml
    # Values from Git
    - repoURL: https://github.com/fzymgc-house/selfhosted-cluster.git
      targetRevision: main
      ref: values
    # Supporting resources (namespace, secrets, postgres)
    - repoURL: https://github.com/fzymgc-house/selfhosted-cluster.git
      targetRevision: main
      path: argocd/app-configs/teleport
  destination:
    server: https://kubernetes.default.svc
    namespace: teleport
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

**Step 2: Commit**

```bash
git add argocd/applications/teleport.yaml
git commit -m "feat(teleport): Add ArgoCD Application for Teleport deployment"
```

---

## Phase 3: Authentik OIDC Integration

### Task 3.1: Create Authentik Groups for Teleport

**Files:**
- Create: `tf/authentik/teleport.tf`

**Step 1: Create Authentik Terraform configuration**

```hcl
# tf/authentik/teleport.tf

# Groups for Teleport access control
resource "authentik_group" "teleport_users" {
  name = "teleport-users"
}

resource "authentik_group" "teleport_admins" {
  name         = "teleport-admins"
  parent       = authentik_group.teleport_users.id
  is_superuser = false
}

# OAuth2 Provider for Teleport
resource "authentik_provider_oauth2" "teleport" {
  name        = "Teleport"
  client_type = "confidential"
  client_id   = "teleport"

  authorization_flow = data.authentik_flow.default_provider_authorization_explicit_consent.id
  invalidation_flow  = data.authentik_flow.default_provider_invalidation_flow.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://teleport.fzymgc.house/v1/webapi/oidc/callback"
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
  ]

  signing_key = data.authentik_certificate_key_pair.tls.id

  # Include groups claim
  sub_mode = "user_email"
}

# Application wrapper
resource "authentik_application" "teleport" {
  name              = "Teleport"
  slug              = "teleport"
  protocol_provider = authentik_provider_oauth2.teleport.id
  meta_launch_url   = "https://teleport.fzymgc.house"
  meta_description  = "Zero-trust access platform for SSH and Kubernetes"
  meta_publisher    = "Gravitational"

  lifecycle {
    ignore_changes = [
      meta_icon
    ]
  }
}

# Policy binding for teleport-users group
resource "authentik_policy_binding" "teleport_users_access" {
  target = authentik_application.teleport.uuid
  group  = authentik_group.teleport_users.id
  order  = 0
}

# Store OAuth2 credentials in Vault
resource "vault_kv_secret_v2" "teleport_oidc" {
  mount = "secret"
  name  = "fzymgc-house/cluster/teleport/oidc"

  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.teleport.client_id
    client_secret = authentik_provider_oauth2.teleport.client_secret
    issuer_url    = "https://auth.fzymgc.house/application/o/teleport/"
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by  = "terraform"
      application = "teleport"
    }
  }
}

# Output for reference
output "teleport_oidc_client_id" {
  value = authentik_provider_oauth2.teleport.client_id
}
```

**Step 2: Format and validate**

```bash
cd tf/authentik
terraform fmt
terraform validate
```

**Step 3: Plan and apply**

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

**Step 4: Commit**

```bash
git add tf/authentik/teleport.tf
git commit -m "feat(authentik): Add OIDC provider and groups for Teleport"
```

---

### Task 3.2: Create ExternalSecret for OIDC Credentials

**Files:**
- Create: `argocd/app-configs/teleport/oidc-secret.yaml`
- Modify: `argocd/app-configs/teleport/kustomization.yaml`

**Step 1: Create the ExternalSecret**

```yaml
# argocd/app-configs/teleport/oidc-secret.yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: teleport-oidc
  namespace: teleport
spec:
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: teleport-oidc
    creationPolicy: Owner
    deletionPolicy: Delete
    template:
      type: Opaque
      data:
        client_id: "{{ .client_id }}"
        client_secret: "{{ .client_secret }}"
        issuer_url: "{{ .issuer_url }}"
  data:
    - secretKey: client_id
      remoteRef:
        key: fzymgc-house/cluster/teleport/oidc
        property: client_id
    - secretKey: client_secret
      remoteRef:
        key: fzymgc-house/cluster/teleport/oidc
        property: client_secret
    - secretKey: issuer_url
      remoteRef:
        key: fzymgc-house/cluster/teleport/oidc
        property: issuer_url
```

**Step 2: Update kustomization.yaml**

```yaml
# argocd/app-configs/teleport/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - rbac.yaml
  - db-secrets.yaml
  - join-token-secret.yaml
  - oidc-secret.yaml
  - certificate.yaml
  - postgres-cluster.yaml
```

**Step 3: Commit**

```bash
git add argocd/app-configs/teleport/
git commit -m "feat(teleport): Add ExternalSecret for OIDC credentials"
```

---

### Task 3.3: Create Teleport OIDC Connector Resource

**Files:**
- Create: `argocd/app-configs/teleport/oidc-connector.yaml`
- Modify: `argocd/app-configs/teleport/kustomization.yaml`

**Step 1: Create the OIDC connector as a Teleport resource**

Note: This will be applied via `tctl` after Teleport is running.

```yaml
# argocd/app-configs/teleport/oidc-connector.yaml
# This is a Teleport resource, not a Kubernetes resource
# Apply with: tctl create -f oidc-connector.yaml
kind: oidc
version: v3
metadata:
  name: authentik
spec:
  issuer_url: https://auth.fzymgc.house/application/o/teleport/
  client_id: teleport
  client_secret_file: /etc/teleport-oidc/client_secret
  redirect_url: https://teleport.fzymgc.house/v1/webapi/oidc/callback
  display: "Login with Authentik"
  scope:
    - openid
    - profile
    - email
    - groups
  claims_to_roles:
    - claim: groups
      value: teleport-admins
      roles:
        - admin
    - claim: groups
      value: teleport-users
      roles:
        - access
```

**Step 2: Commit**

```bash
git add argocd/app-configs/teleport/oidc-connector.yaml
git commit -m "feat(teleport): Add OIDC connector configuration for Authentik"
```

---

### Task 3.4: Create Teleport Roles

**Files:**
- Create: `argocd/app-configs/teleport/roles.yaml`

**Step 1: Create Teleport role definitions**

```yaml
# argocd/app-configs/teleport/roles.yaml
# Apply with: tctl create -f roles.yaml
---
kind: role
version: v7
metadata:
  name: admin
spec:
  allow:
    logins:
      - root
      - "{{internal.logins}}"
    node_labels:
      "*": "*"
    kubernetes_labels:
      "*": "*"
    kubernetes_groups:
      - system:masters
    kubernetes_resources:
      - kind: "*"
        namespace: "*"
        name: "*"
        verbs: ["*"]
    rules:
      - resources: ["*"]
        verbs: ["*"]
  options:
    forward_agent: true
    max_session_ttl: 12h
---
kind: role
version: v7
metadata:
  name: access
spec:
  allow:
    logins:
      - "{{internal.logins}}"
      - "{{email.local(external.email)}}"
    node_labels:
      env: production
    kubernetes_labels:
      "*": "*"
    kubernetes_groups:
      - view
    kubernetes_resources:
      - kind: pod
        namespace: "*"
        name: "*"
        verbs: ["get", "list", "watch"]
      - kind: pod/exec
        namespace: "*"
        name: "*"
        verbs: ["create"]
      - kind: pod/log
        namespace: "*"
        name: "*"
        verbs: ["get", "list"]
  options:
    forward_agent: false
    max_session_ttl: 8h
```

**Step 2: Commit**

```bash
git add argocd/app-configs/teleport/roles.yaml
git commit -m "feat(teleport): Add admin and access role definitions"
```

---

## Phase 4: Kubernetes Access Configuration

### Task 4.1: Update Helm Values for OIDC

**Files:**
- Modify: `argocd/app-configs/teleport/values.yaml`

**Step 1: Update values.yaml to include OIDC volume mounts**

Add to the existing values.yaml:

```yaml
# Add OIDC secret volume
extraVolumes:
  - name: teleport-db-certs
    secret:
      secretName: teleport-db-ca
  - name: teleport-join-token
    secret:
      secretName: teleport-join-token
  - name: teleport-oidc
    secret:
      secretName: teleport-oidc

extraVolumeMounts:
  - name: teleport-db-certs
    mountPath: /etc/teleport-db-certs
    readOnly: true
  - name: teleport-join-token
    mountPath: /etc/teleport-join-token
    readOnly: true
  - name: teleport-oidc
    mountPath: /etc/teleport-oidc
    readOnly: true
```

**Step 2: Commit**

```bash
git add argocd/app-configs/teleport/values.yaml
git commit -m "feat(teleport): Add OIDC secret volume mount to Helm values"
```

---

## Phase 5: Node SSH Access (Ansible)

### Task 5.1: Create Teleport Agent Ansible Role Structure

**Files:**
- Create: `ansible/roles/teleport-agent/tasks/main.yml`
- Create: `ansible/roles/teleport-agent/templates/teleport.yaml.j2`
- Create: `ansible/roles/teleport-agent/defaults/main.yml`
- Create: `ansible/roles/teleport-agent/handlers/main.yml`

**Step 1: Create role directory structure**

```bash
mkdir -p ansible/roles/teleport-agent/{tasks,templates,defaults,handlers}
```

**Step 2: Create defaults/main.yml**

```yaml
# ansible/roles/teleport-agent/defaults/main.yml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
---
teleport_version: "17"
teleport_auth_server: "teleport.fzymgc.house:443"
teleport_node_labels:
  env: production
```

**Step 3: Create tasks/main.yml**

```yaml
# ansible/roles/teleport-agent/tasks/main.yml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
---
- name: Add Teleport APT repository key
  ansible.builtin.apt_key:
    url: https://apt.releases.teleport.dev/gpg
    state: present
  become: true
  tags:
    - teleport-agent

- name: Add Teleport APT repository
  ansible.builtin.apt_repository:
    repo: "deb https://apt.releases.teleport.dev/ubuntu {{ ansible_distribution_release }} stable/v{{ teleport_version }}"
    state: present
    filename: teleport
  become: true
  tags:
    - teleport-agent

- name: Install Teleport package
  ansible.builtin.apt:
    name: teleport
    state: present
    update_cache: true
  become: true
  tags:
    - teleport-agent

- name: Template Teleport configuration
  ansible.builtin.template:
    src: teleport.yaml.j2
    dest: /etc/teleport.yaml
    owner: root
    group: root
    mode: "0600"
  become: true
  notify:
    - Restart teleport
  tags:
    - teleport-agent

- name: Enable and start Teleport service
  ansible.builtin.systemd:
    name: teleport
    state: started
    enabled: true
  become: true
  tags:
    - teleport-agent
```

**Step 4: Create templates/teleport.yaml.j2**

```yaml
# ansible/roles/teleport-agent/templates/teleport.yaml.j2
# SPDX-License-Identifier: MIT-0
# code: language=jinja2
version: v3
teleport:
  nodename: {{ inventory_hostname }}
  auth_token: {{ teleport_join_token }}
  proxy_server: {{ teleport_auth_server }}
  log:
    severity: INFO
    format:
      output: json

ssh_service:
  enabled: true
  labels:
{% for key, value in teleport_node_labels.items() %}
    {{ key }}: {{ value }}
{% endfor %}
{% if 'control_plane' in group_names %}
    role: control-plane
{% else %}
    role: worker
{% endif %}

auth_service:
  enabled: false

proxy_service:
  enabled: false
```

**Step 5: Create handlers/main.yml**

```yaml
# ansible/roles/teleport-agent/handlers/main.yml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
---
- name: Restart teleport
  ansible.builtin.systemd:
    name: teleport
    state: restarted
  become: true
```

**Step 6: Commit**

```bash
git add ansible/roles/teleport-agent/
git commit -m "feat(ansible): Add teleport-agent role for node SSH access"
```

---

### Task 5.2: Create Teleport Agents Playbook

**Files:**
- Create: `ansible/teleport-agents-playbook.yml`

**Step 1: Create the playbook**

```yaml
# ansible/teleport-agents-playbook.yml
# SPDX-License-Identifier: MIT-0
# code: language=ansible
---
- name: Deploy Teleport SSH agents to cluster nodes
  hosts: tp_cluster_nodes
  gather_facts: true

  vars:
    # Fetch join token from Vault
    teleport_join_token: "{{ lookup('community.hashi_vault.hashi_vault', 'secret/data/fzymgc-house/cluster/teleport/join-token:token') }}"

  roles:
    - role: teleport-agent
      tags:
        - teleport-agent
```

**Step 2: Commit**

```bash
git add ansible/teleport-agents-playbook.yml
git commit -m "feat(ansible): Add playbook for deploying Teleport agents to nodes"
```

---

## Post-Deployment Tasks

### Task 6.1: Manual Steps After Deployment

After ArgoCD syncs the Teleport deployment:

**Step 1: Wait for PostgreSQL to be ready**

```bash
kubectl --context fzymgc-house wait --for=condition=Ready cluster/teleport-db -n teleport --timeout=300s
```

**Step 2: Wait for Teleport pods to be ready**

```bash
kubectl --context fzymgc-house wait --for=condition=Ready pod -l app.kubernetes.io/name=teleport -n teleport --timeout=300s
```

**Step 3: Create initial admin user (local auth)**

```bash
kubectl --context fzymgc-house exec -n teleport deployment/teleport-auth -- tctl users add admin --roles=admin --logins=root,admin
```

**Step 4: Apply OIDC connector**

```bash
kubectl --context fzymgc-house exec -n teleport deployment/teleport-auth -- tctl create -f /path/to/oidc-connector.yaml
```

**Step 5: Apply roles**

```bash
kubectl --context fzymgc-house exec -n teleport deployment/teleport-auth -- tctl create -f /path/to/roles.yaml
```

**Step 6: Deploy node agents via Ansible**

```bash
source .venv/bin/activate
ansible-playbook -i ansible/inventory/hosts.yml ansible/teleport-agents-playbook.yml
```

**Step 7: Verify node registration**

```bash
kubectl --context fzymgc-house exec -n teleport deployment/teleport-auth -- tctl nodes ls
```

---

## Verification Checklist

- [ ] PostgreSQL cluster is running and healthy
- [ ] Teleport auth pods are running
- [ ] Teleport proxy pods are running
- [ ] TLS certificate is issued by cert-manager
- [ ] Web UI accessible at https://teleport.fzymgc.house
- [ ] Local admin user can log in
- [ ] OIDC login with Authentik works
- [ ] `tsh login` works from CLI
- [ ] `tsh kube login fzymgc-house` works
- [ ] `kubectl` commands work through Teleport
- [ ] Node agents are registered
- [ ] `tsh ssh` to nodes works
- [ ] Session recording is enabled
