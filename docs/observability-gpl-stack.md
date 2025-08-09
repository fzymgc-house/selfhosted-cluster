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
  - Loki S3 creds: `kv/data/observability/loki`
  - Alertmanager config: `kv/data/observability/alertmanager`

### Task checklist
- [x] Helm repo for Grafana charts added under `flux-system`
- [x] `monitoring` (and `loki` if separate) namespaces created
- [ ] `kube-prometheus-stack` HelmRelease
  - [ ] Disable bundled Grafana
  - [ ] Prometheus 2 replicas, 50Gi PVC, retention 15d, anti-affinity, PDB
  - [ ] Alertmanager 3 replicas, anti-affinity, PDB
  - [ ] ServiceMonitors/PodMonitors discovery enabled
  - [ ] IngressRoutes with TLS and `modern-auth` (optional)
  - [ ] ExternalSecret for `alertmanager-config`
- [ ] Loki distributed HelmRelease
  - [ ] R2 object storage via ExternalSecret
  - [ ] 3x for critical components; anti-affinity; PDBs
  - [ ] Retention 14d; PVCs if required
  - [ ] NetworkPolicy to restrict ingress
- [ ] Grafana Alloy HelmRelease (agent)
  - [ ] Kubernetes autodiscovery and container logs collection (filelog)
  - [ ] Ship logs to Loki service inside cluster
  - [ ] Tolerations for control-plane; resource limits
  - [ ] Egress restricted to Loki service
- [ ] Grafana integration
  - [ ] `GrafanaDatasource` for Prometheus
  - [ ] `GrafanaDatasource` for Loki
  - [ ] Curated `GrafanaDashboard` CRs added
- [ ] Flux wiring
  - [x] `fluxcd/apps/main/kustomization.yaml` includes `./monitoring`
  - [ ] Reconciliation order validated (secrets -> releases)
- [ ] Validation
  - [ ] Grafana datasources green
  - [ ] Prometheus targets up (kube, velero, etc.)
  - [ ] Loki queries return logs
  - [ ] Test alert delivered (Slack/Webhook)

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
