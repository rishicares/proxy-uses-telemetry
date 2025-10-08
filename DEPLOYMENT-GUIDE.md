# Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying the proxy usage telemetry solution in a Kubernetes cluster.

## Prerequisites

- Kubernetes cluster (minikube, k3s, or production cluster)
- kubectl CLI configured
- Helm 3.x installed
- Istio 1.20+ installed (or use auto-install)
- Sufficient resources for your deployment scale

## Quick Start

### One-Command Deployment

The simplest way to deploy everything:

```bash
./deploy.sh
```

This script will automatically:
1. Clean up any existing deployment
2. Deploy the complete stack (Istio + Prometheus + Grafana + Load Generators)
3. Validate metrics collection
4. Offer to open dashboards (port-forward + browser)

When prompted "Would you like to open dashboards now?", answer **y** and:
- Port forwards start automatically
- Grafana opens in your browser at http://localhost:3000 (admin/admin)
- Prometheus available at http://localhost:9090

**That's it!** Everything is automated.

### Manual Step-by-Step (Alternative)

If you prefer manual control:

#### 1. Bootstrap Cluster (Optional)

If starting from scratch with minikube:

```bash
./scripts/bootstrap-cluster.sh
```

This script will:
- Start minikube with appropriate resources
- Install Istio service mesh
- Configure namespaces with sidecar injection

#### 2. Install the Solution

```bash
helm install proxy-telemetry ./helm/proxy-telemetry -n monitoring --create-namespace --wait --timeout 15m
```

#### 3. Verify Installation

Run validation:

```bash
./scripts/validate-istio-metrics.sh
```

#### 4. Access Dashboards

Use the dashboard script:

```bash
./scripts/open-dashboards.sh
```

Or manually:

```bash
kubectl port-forward -n monitoring svc/grafana 3000:80 &
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
```

Access dashboards:
- Grafana: http://localhost:3000 (admin/admin)
- Prometheus: http://localhost:9090

## Configuration

### Traffic Generation Settings

Edit `helm/proxy-telemetry/values.yaml`:

```yaml
loadGenerator:
  replicas: 9  # Total pods across all vendors (configurable)
  traffic:
    requestsPerSecond: 100  # Per pod
    concurrentRequests: 100
```

Traffic generation depends on replica count and requests per second configuration

### Resource Limits

Current settings per pod:

```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "500m"
  limits:
    memory: "1Gi"
    cpu: "1000m"
```

Total cluster requirement: ~11 CPU cores, ~11GB RAM

### Proxy Vendors

Configure vendors in values.yaml:

```yaml
vendors:
  - name: vendor-a
    weight: 40  # Percentage of traffic
  - name: vendor-b
    weight: 35
  - name: vendor-c
    weight: 25
```

## Scaling

### Increase Traffic Volume

Horizontal scaling:

```bash
kubectl scale deployment -n crawlers \
  load-generator-vendor-a \
  load-generator-vendor-b \
  load-generator-vendor-c \
  --replicas=10
```

Vertical scaling (requests per second):

```bash
kubectl set env deployment -n crawlers -l app=load-generator \
  REQUESTS_PER_SECOND=200
```

### Adjust Resources

Update resource limits if needed:

```bash
kubectl set resources deployment -n crawlers -l app=load-generator \
  --limits=cpu=2000m,memory=2Gi \
  --requests=cpu=1000m,memory=1Gi \
  -c load-generator
```

## Troubleshooting

### No Metrics Appearing

Check Istio sidecar injection:

```bash
kubectl get namespace crawlers --show-labels
# Should have: istio-injection=enabled

kubectl get pods -n crawlers
# Should show: 2/2 READY (app + istio-proxy)
```

If sidecars missing:

```bash
kubectl label namespace crawlers istio-injection=enabled --overwrite
kubectl rollout restart deployment -n crawlers -l app=load-generator
```

### Pods Pending

Check node resources:

```bash
kubectl top nodes
kubectl describe nodes
```

Reduce replicas if insufficient resources:

```bash
kubectl scale deployment -n crawlers -l app=load-generator --replicas=5
```

### High Error Rates

Check external connectivity:

```bash
kubectl logs -n crawlers -l app=load-generator -c load-generator --tail=50
```

Common issues:
- DNS resolution failures
- Rate limiting from external sites
- Network timeouts (expected occasionally)

## Metrics Validation

### Verify Data Collection

Query Prometheus (port 9090):

```promql
# Request rate by vendor
sum by (proxy_vendor) (rate(envoy_cluster_upstream_rq_total[1m]))

# Bandwidth sent
sum by (proxy_vendor) (rate(envoy_cluster_upstream_cx_tx_bytes_total[1m]))

# Bandwidth received  
sum by (proxy_vendor) (rate(envoy_cluster_upstream_cx_rx_bytes_total[1m]))

# Top destinations
topk(10, sum by (destination_host) (rate(envoy_cluster_upstream_rq_total[1m])))
```

### Expected Results

With default configuration (21 pods, 100 req/s each):

- Total request rate: ~2,100 requests/second
- Per vendor: ~700 requests/second
- Total bandwidth: ~20-25 MB/s
- Response success rate: >95%

## Production Deployment

### Before Production

1. Change default credentials:

```yaml
grafana:
  adminPassword: <secure-password>
```

2. Configure persistent storage:

```yaml
prometheus:
  storage:
    volumeSize: 500Gi
    storageClassName: <production-storage-class>

grafana:
  persistence:
    size: 100Gi
    storageClassName: <production-storage-class>
```

3. Enable SSL/TLS:

Update load generator to verify SSL certificates by removing `ssl=False` from the code.

4. Configure network policies:

Create NetworkPolicy resources to restrict traffic between namespaces.

5. Set up alerting:

Configure Alertmanager endpoints in prometheus.yml:

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
```

### Resource Planning

For production workloads:

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| Prometheus | 4 cores | 8Gi | 500Gi |
| Grafana | 1 core | 1Gi | 100Gi |
| Load Generator (per pod) | 500m | 512Mi | - |
| Load Generator (21 pods) | 10.5 cores | 10.5Gi | - |
| **Total** | **~16 cores** | **~20Gi** | **600Gi** |

### High Availability

For HA deployment:

```yaml
prometheus:
  replicaCount: 2
  
grafana:
  replicaCount: 2
  
loadGenerator:
  autoscaling:
    enabled: true
    minReplicas: 6
    maxReplicas: 50
```

## Maintenance

### Update Configuration

To update running configuration:

```bash
helm upgrade proxy-telemetry ./helm/proxy-telemetry -n monitoring
```

### Check Health

Regular health checks:

```bash
# Pod status
kubectl get pods -n crawlers -n monitoring

# Resource usage
kubectl top pods -n crawlers -n monitoring

# Recent events
kubectl get events -n crawlers --sort-by='.lastTimestamp' | tail -20
```

### Backup

Backup Prometheus data:

```bash
kubectl exec -n monitoring prometheus-xxx -- tar czf /tmp/prometheus-backup.tar.gz /prometheus
kubectl cp monitoring/prometheus-xxx:/tmp/prometheus-backup.tar.gz ./prometheus-backup.tar.gz
```

## Uninstall

Remove the deployment:

```bash
helm uninstall proxy-telemetry -n monitoring
kubectl delete namespace crawlers monitoring
```

## Support

For issues or questions:
1. Check logs: `kubectl logs -n crawlers <pod-name> -c load-generator`
2. Run validation: `./scripts/validate-istio-metrics.sh`
3. Review documentation in this repository

## References

- Architecture: `ARCHITECTURE.md`
- Data Model: `DATA-MODEL.md`
- Configuration Changes: `CHANGES.md`
- Project Structure: `PROJECT-STRUCTURE.md`
