## Observability GPL stack plan

### Goals
- Stand up Prometheus, Alertmanager, Loki, and Grafana Alloy with Grafana as the UI
- GitOps-first via FluxCD; HA, secure by default; Vault-backed secrets; TLS via Traefik

### Architecture
- **metrics**: `kube-prometheus-stack` (Prometheus Operator)
- **logs/agent**: `loki-distributed` + **Grafana Alloy** as the node agent (replaces Promtail; can also handle OTel)
- **dashboards**: existing Grafana via Operator with `GrafanaDatasource`/`GrafanaDashboard` CRs

### Repo layout (proposed)
- **helm repos**: `fluxcd/infrastructure/controllers/helm-repositories/grafana.yaml`
- **apps**:
  - `fluxcd/apps/main/monitoring/namespace.yaml`
  - `fluxcd/apps/main/monitoring/kube-prometheus-stack/helm-install.yaml`
  - `fluxcd/apps/main/monitoring/kube-prometheus-stack/kustomization.yaml`
  - `fluxcd/apps/main/monitoring/loki/helm-install.yaml`
  - `fluxcd/apps/main/monitoring/loki/external-secret-s3.yaml`
  - `fluxcd/apps/main/monitoring/loki/kustomization.yaml`
  - `fluxcd/apps/main/monitoring/alloy/helm-install.yaml`
  - `fluxcd/apps/main/monitoring/alloy/kustomization.yaml`
  - `fluxcd/apps/main/grafana/datasources/prometheus-ds.yaml`
  - `fluxcd/apps/main/grafana/datasources/loki-ds.yaml`
  - `fluxcd/apps/main/grafana/dashboards/*.yaml`

### Decisions to confirm
- **hostnames**: `prometheus.k8s.fzymgc.house`, `alerts.k8s.fzymgc.house` (via Traefik + `modern-auth`)
- **retention**: metrics 15d, logs 14d
- **storage**: Prometheus PVC 50Gi on `longhorn`; Loki object store in R2
- **Vault paths**:
  - Loki R2 creds: `fzymgc-house/cluster/loki` with keys `bucket`, `endpoint`, `region`, `r2_access_key_id`, `r2_secret_access_key`
  - Alertmanager config: `kv/data/observability/alertmanager`

### Task checklist
- [x] Helm repo for Grafana charts added under `flux-system`
- [x] `monitoring` (and `loki` if separate) namespaces created
- [ ] `kube-prometheus-stack` HelmRelease
  - [x] Disable bundled Grafana
  - [x] Prometheus 2 replicas, 50Gi PVC, retention 15d, anti-affinity, PDB
  - [x] Alertmanager 3 replicas, anti-affinity, PDB
  - [x] ServiceMonitors/PodMonitors discovery enabled
  - [x] IngressRoutes with TLS and `modern-auth` (optional)
  - [x] ExternalSecret for `alertmanager-config`
- [ ] Loki distributed HelmRelease
  - [x] R2 object storage via ExternalSecret
  - [x] 3x for critical components; anti-affinity; PDBs (replicas set; PDBs created; anti-affinity added)
  - [x] Resource requests/limits defined for all components
  - [x] Retention 14d; PVCs if required
  - [x] NetworkPolicy to restrict ingress
  - [x] Switch to TSDB storage schema
- [ ] Grafana Alloy HelmRelease (agent)
  - [x] Kubernetes autodiscovery and container logs collection (filelog)
  - [x] Ship logs to Loki service inside cluster
  - [x] Tolerations for control-plane; resource limits
  - [x] Egress restricted to Loki service
  - [x] Allow egress to kube-dns (53 TCP/UDP) and Kubernetes API (443)
- [ ] Grafana integration
  - [x] `GrafanaDatasource` for Prometheus
  - [x] `GrafanaDatasource` for Loki
  - [ ] Curated `GrafanaDashboard` CRs added
- [ ] Flux wiring
  - [x] `fluxcd/apps/main/kustomization.yaml` includes `./monitoring`
  - [ ] Reconciliation order validated (secrets -> releases)
- [ ] Validation
  - [ ] Grafana datasources green
  - [ ] Prometheus targets up (kube, velero, etc.)
  - [ ] Loki queries return logs
  - [ ] Test alert delivered (Slack/Webhook)

### Follow-ups from PR review
- [x] Loki storage schema: update to current TSDB configuration (or confirm `schemaConfig` compatibility) and document any migration steps if changing schemas.
- [x] Normalize Loki URLs: use a single gateway URL consistently in Alloy and Grafana (e.g., `http://loki-distributed-gateway.monitoring.svc.cluster.local`).
- [x] Include NetworkPolicies in kustomizations: add `networkpolicies.yaml` to `monitoring/loki/kustomization.yaml` and `monitoring/alloy/kustomization.yaml`.
- [x] Alloy config improvements: enable Kubernetes metadata enrichment, multiline parsing, and filtering for noisy logs (e.g., `kube-system` churn) using Alloy modules (`loki.source.kubernetes`, relabel rules).
- [x] Set explicit resource requests/limits for Prometheus and Alertmanager as well.
- [x] Add per-component PDBs and anti-affinity settings for Loki where supported by the chart.
- [ ] Add curated Kubernetes and Loki dashboards under `fluxcd/apps/main/grafana/dashboards/` and organize into folders.

### Rollout order
1. Add Helm repo(s) and namespaces
2. Add ExternalSecrets for Loki and Alertmanager
3. Deploy `kube-prometheus-stack`
4. Deploy Loki, then Grafana Alloy
5. Add Grafana datasources and dashboards
6. Expose Prometheus/Alertmanager (optional)

### Notes
- Use `longhorn` StorageClass for PVCs
- Reuse TLS secret `wildcard-fzymgc-house-tls`
- Keep services internal unless external access is required
- Prefer NetworkPolicies to minimize blast radius
