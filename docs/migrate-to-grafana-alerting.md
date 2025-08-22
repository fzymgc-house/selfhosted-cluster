### Migrate Alerting from Alertmanager to Grafana Unified Alerting (with Discord Notifications)

This document describes how to replace Prometheus Alertmanager with Grafana Unified Alerting managed by Grafana Operator, while sending notifications to Discord using Grafana's native Discord integration. The plan follows GitOps-first principles with FluxCD and keeps secrets in Vault via External Secrets.

---

## Goals

- Replace Alertmanager with Grafana Unified Alerting
- Manage alert rules, contact points, notification policies as Kubernetes CRDs via Grafana Operator
- Use Discord as the notification path
- Keep GitOps, HA, and security-by-default intact

## Current State (as of repo)

- Alerting stack:
  - `kube-prometheus-stack` installs Prometheus and Alertmanager
    - Alertmanager configured via Vault
      - `fluxcd/apps/main/monitoring/kube-prometheus-stack/alertmanager-external-secret.yaml`
      - `fluxcd/apps/main/monitoring/kube-prometheus-stack/helm-install.yaml` (values.alertmanager)
    - Public route to Alertmanager
      - `fluxcd/apps/main/monitoring/kube-prometheus-stack/ingressroutes.yaml` (host `alerts.k8s.fzymgc.house`)
  - Discord notifications today are handled via a bridge:
    - `fluxcd/apps/main/monitoring/alertmanager-discord/*` (Deployment + Service + ExternalSecret)
    - Alertmanager sends webhooks to this bridge, which posts into Discord
- Grafana stack:
  - Grafana Operator installed (`fluxcd/apps/main/grafana-operator/*`)
  - Grafana instance managed (`fluxcd/apps/main/grafana/grafana.yaml`)
  - Prometheus datasource present (`fluxcd/apps/main/grafana/datasources/prometheus-ds.yaml`)

## Target Architecture

- Grafana Unified Alerting is the only alerting/notification engine
- Alert definitions are managed as CRDs via Grafana Operator:
  - GrafanaRuleGroup: alert rule groups (PromQL queries run against Prometheus datasource)
  - GrafanaContactPoint: destinations (Discord via webhook)
  - GrafanaNotificationPolicy: routing tree for alerts
  - GrafanaMuteTiming (optional): maintenance windows
- Discord notifications use a native Discord contact point in Grafana. The Discord webhook URL is sourced from Vault via External Secrets into a `Secret` in the `grafana` namespace and referenced by the contact point. No `alertmanager-discord` bridge is required.

Diagram (high-level):

```
Prometheus ──(scrape + rules disabled for notif)──▶ Grafana (Unified Alerting)
    ▲                                               │
    │ Prometheus DS                                  └─(native Discord contact point)─▶ Discord
    └────────────────────────────────────────────────┘
```

## Migration Plan

### Phase 0 – Prerequisites

- Ensure Grafana is healthy and reachable at `grafana.fzymgc.house` and is >= 9.0
- Confirm Grafana Operator v5.x is installed (repo uses `v5.18.0`)
- Prometheus datasource is present and default (already configured)

### Phase 1 – Introduce Grafana Alerting CRDs

1) Create a Secret for the Discord webhook URL via External Secrets (Vault → Kubernetes Secret):

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: grafana-discord-webhook
  namespace: grafana
spec:
  refreshInterval: 5m
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault
  target:
    name: grafana-discord-webhook
    creationPolicy: Owner
  data:
    - secretKey: WEBHOOK_URL
      remoteRef:
        key: fzymgc-house/cluster/alerting
        property: discord-webhook-url
```

2) Create a native Discord Contact Point in Grafana. Depending on Grafana Operator version, either reference the URL directly in `settings.url` or use secure/secret fields. Prefer secret-based configuration.

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaContactPoint
metadata:
  name: cp-discord
  namespace: grafana
  labels:
    grafana.integreatly.org/instance: grafana
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  contactPoints:
    - name: discord
      receivers:
        - uid: discord-native
          type: discord
          # Option A: Inline (not recommended). Use only for testing.
          # settings:
          #   url: https://discord.com/api/webhooks/...
          # Option B: Secret-backed (recommended). Exact fields may vary by operator version.
          # The operator supports secret references for sensitive fields; consult your installed CRD docs.
          settings:
            url: ${DISCORD_WEBHOOK_URL}
          secureFields:
            - name: DISCORD_WEBHOOK_URL
              valueFrom:
                secretKeyRef:
                  name: grafana-discord-webhook
                  key: WEBHOOK_URL
```

3) Create a default Notification Policy that routes everything to the Discord contact point. Adjust grouping as desired.

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaNotificationPolicy
metadata:
  name: np-default
  namespace: grafana
  labels:
    grafana.integreatly.org/instance: grafana
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  policy:
    # Default policy at root
    receiver: discord
    groupBy:
      - alertname
      - severity
    # Optional: create sub-routes for severities
    routes:
      - objectMatchers:
          - [ severity, =, critical ]
        receiver: discord
        groupWait: 0s
        groupInterval: 1m
        repeatInterval: 5m
```

4) Optional: Define mute timings for maintenance windows.

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaMuteTiming
metadata:
  name: mt-maintenance
  namespace: grafana
  labels:
    grafana.integreatly.org/instance: grafana
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  muteTimings:
    - name: maintenance
      timeIntervals:
        - times:
            - startTime: '22:00'
              endTime: '23:00'
```

5) Start with an initial Rule Group in Grafana to replace a critical alert (example: API server up). Expand iteratively.

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaRuleGroup
metadata:
  name: rg-kubernetes-critical
  namespace: grafana
  labels:
    grafana.integreatly.org/instance: grafana
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  folders:
    - title: Kubernetes
      interval: 1m
      orgId: 1
      rules:
        - title: KubeAPI is down
          condition: A
          data:
            - refId: A
              datasourceUid: Prometheus
              relativeTimeRange:
                from: 300
                to: 0
              model:
                datasource:
                  type: prometheus
                  uid: Prometheus
                editorMode: code
                expr: up{job="apiserver"} == 0
                intervalMs: 60000
                legendFormat: ""
                maxDataPoints: 43200
                refId: A
          for: 2m
          annotations:
            summary: "Kubernetes API server appears down"
            runbook_url: "https://runbooks.internal/kubeapi"
          labels:
            severity: critical
          noDataState: NoData
          execErrState: Error
```

Notes:
- `datasourceUid: Prometheus` must match the UID of the Prometheus datasource created by `GrafanaDatasource` (operator will set one; verify in Grafana UI or supply `uid` in the datasource CR).
- The rule group structure mirrors how you would create alerts in the Grafana UI; the operator CRD applies the same.

### Phase 2 – Disable Alertmanager and Alertmanager-specific bits

In `fluxcd/apps/main/monitoring/kube-prometheus-stack/helm-install.yaml`:
- Set `values.alertmanager.enabled: false` (add if missing)
- Remove or ignore `values.alertmanager.configSecret`
- Keep Prometheus running

Example values delta (conceptual):

```yaml
spec:
  values:
    grafana:
      enabled: false
    alertmanager:
      enabled: false
    prometheus:
      # unchanged
```

Remove Alertmanager-specific resources from Kustomization:
- Delete `fluxcd/apps/main/monitoring/kube-prometheus-stack/alertmanager-external-secret.yaml`
- Remove Alertmanager IngressRoute from `fluxcd/apps/main/monitoring/kube-prometheus-stack/ingressroutes.yaml` (the `alertmanager` block)
- Remove the `alertmanager-discord` Deployment/Service and its ExternalSecret in `fluxcd/apps/main/monitoring/alertmanager-discord/*` (no longer needed)

### Phase 3 – Address PrometheusRules overlap

`kube-prometheus-stack` ships a large set of `PrometheusRule` CRs. With Alertmanager disabled, those rules will still evaluate inside Prometheus but won’t notify. Options:

- Minimal: leave them as-is for now; begin porting high-value alerts into Grafana rule groups
- Preferred: disable default alert rules in the chart and explicitly author Grafana rule groups

Chart values (example) to disable defaults:

```yaml
spec:
  values:
    defaultRules:
      create: false
```

or selectively disable groups under `defaultRules.rules.*` if you want to keep a subset running.

### Phase 4 – Validate

- Reconcile Flux and verify CRDs applied:
  - Contact Point exists and reachable (Grafana UI → Alerting → Contact points)
  - Notification Policy routes to `discord`
  - Rule Group evaluates successfully
- Create a synthetic alert rule to fire and confirm Discord receives a message directly in the target Discord channel
- Check Grafana and operator logs for errors

### Phase 5 – Clean-up (optional)

- If/when moving Grafana to post directly to Discord:
  - Create a Secret in `grafana` namespace from Vault via External Secrets with the Discord webhook URL
  - Update `GrafanaContactPoint` to use the Discord webhook URL directly
  - Remove `alertmanager-discord` Deployment/Service

### Rollback Plan

- Re-enable Alertmanager in `kube-prometheus-stack` values and restore `alertmanager-external-secret.yaml`
- Re-apply the Alertmanager IngressRoute
- Remove/ignore Grafana alerting CRDs if they conflict

## Implementation Checklist (GitOps)

- [ ] Add new CRDs:
  - [ ] `ExternalSecret` (Discord webhook URL → `grafana-discord-webhook` Secret)
  - [ ] `GrafanaContactPoint` (native `discord` integration using secret-backed webhook URL)
  - [ ] `GrafanaNotificationPolicy` (default to `discord`, add critical route)
  - [ ] `GrafanaRuleGroup` (start with a small, critical set)
  - [ ] Optional `GrafanaMuteTiming`
- [ ] Disable Alertmanager via HelmRelease values
- [ ] Remove Alertmanager ExternalSecret, IngressRoute, and the `alertmanager-discord` bridge
- [ ] Validate alerts fire to Discord

## Future Enhancements

- Add multiple contact points (Discord channel per severity/team)
- Add routing by namespace/app labels
- Add silence/mute windows via `GrafanaMuteTiming`
- Add Loki-based log alerts as additional rule groups

---

References
- `fluxcd/apps/main/monitoring/kube-prometheus-stack/helm-install.yaml`
- `fluxcd/apps/main/monitoring/kube-prometheus-stack/alertmanager-external-secret.yaml`
- `fluxcd/apps/main/monitoring/kube-prometheus-stack/ingressroutes.yaml`
- `fluxcd/apps/main/monitoring/alertmanager-discord/*`
- `fluxcd/apps/main/grafana-operator/*`
- `fluxcd/apps/main/grafana/*`


