# Observability

GPU and Slurm metrics flow into **GKE Managed Prometheus** (enabled on the
cluster in Terraform). Two ways to view them:

## Option A: Cloud Monitoring (zero extra deploy)

Because the cluster enables the managed `DCGM` component, per-GPU metrics
(utilization, memory, SM activity, power, NVLink) are collected automatically
and visible in Cloud Monitoring under the GKE / GPU dashboards. The Slurm
metrics scraped by `podmonitoring-slurm.yaml` are queryable there too.

## Option B: Self-hosted Grafana (richer dashboards)

```bash
# 1. Query frontend so Grafana can read managed Prometheus
PROJECT_ID=<proj> envsubst < observability/gmp-frontend.yaml.tmpl | kubectl apply -f -

# 2. Slurm scrape config
kubectl apply -f observability/podmonitoring-slurm.yaml

# 3. Grafana with DCGM + node dashboards preloaded
helm repo add grafana https://grafana.github.io/helm-charts
GRAFANA_ADMIN_PASSWORD=changeme \
  envsubst < observability/grafana-values.yaml > /tmp/grafana-values.yaml
helm install grafana grafana/grafana -n monitoring --create-namespace -f /tmp/grafana-values.yaml
```

Per-job GPU attribution is enabled via Slinky's DCGM integration
(`vendor.nvidia.dcgm.enabled: true` in the Slurm values), which labels GPU
metrics with the Slurm job id.
