# Kubernetes Proxy Usage Telemetry

Production-grade observability solution for monitoring outbound proxy usage from thousands of crawler pods in Kubernetes using Istio service mesh.

## Overview

This solution provides complete visibility into proxy usage across large-scale crawler deployments, measuring and attributing all required metrics per the specification:

- **Request count** per proxy vendor
- **Destination tracking** (domain/host)
- **Bandwidth sent** per proxy per pod (outgoing bytes)
- **Bandwidth received** per proxy per pod (incoming bytes)

Supports HTTP, HTTPS, HTTP/1.1, and HTTP/2 protocols with zero application code changes.

## Requirements Coverage

| Requirement | Implementation | Metric/Method |
|-------------|----------------|---------------|
| **a. Request count per proxy** | Istio telemetry with header extraction | `envoy_cluster_upstream_rq_total{proxy_vendor="..."}` |
| **b. Destination tracking** | Envoy cluster metrics | `cluster_name` label contains destination |
| **c. Bandwidth sent (outgoing)** | Envoy connection metrics | `envoy_cluster_upstream_cx_tx_bytes_total` |
| **d. Bandwidth received (incoming)** | Envoy connection metrics | `envoy_cluster_upstream_cx_rx_bytes_total` |
| **HTTP/HTTPS support** | Istio native protocol support | All protocols handled by Envoy proxy |
| **HTTP/1 and HTTP/2** | Istio native protocol support | Automatic protocol detection |
| **Vendor attribution** | Pod label-based | Extracted via Prometheus relabeling |

## Architecture

### High-Level Design

```
Crawler Pod (crawlers namespace)
├── load-generator container
│   └── Adds header: X-Proxy-Vendor: vendor-a
└── istio-proxy sidecar (auto-injected)
    ├── Intercepts all outbound traffic
    ├── Exposes metrics on port 15090
    └── Metrics include pod labels (proxy_vendor)
         ↓
    Prometheus (monitoring namespace)
    ├── Scrapes istio-proxy:15090/stats/prometheus
    ├── Relabels metrics with proxy_vendor from pod labels
    └── Stores: envoy_cluster_upstream_rq_total{proxy_vendor="vendor-a"}
         ↓
    Grafana Dashboards
    ├── Proxy Overview
    ├── Bandwidth Analytics
    ├── Destination Tracking
    └── Performance & Health
```

### Key Components

1. **Istio Service Mesh**
   - Automatic sidecar injection (zero app changes)
   - Traffic interception and telemetry
   - Native HTTP/HTTPS/HTTP2 support

2. **Load Generators** (Synthetic Crawlers)
   - Python async application
   - Adds `X-Proxy-Vendor` header to all requests
   - Simulates 3 proxy vendors (vendor-a, vendor-b, vendor-c)
   - Makes requests to various HTTP/HTTPS endpoints

3. **Prometheus**
   - Scrapes Istio Envoy sidecars (port 15090)
   - Stores time-series metrics with vendor labels
   - 30-day retention (configurable)
   - Recording rules for aggregations

4. **Grafana**
   - 4 pre-built dashboards
   - Real-time visualization
   - Vendor attribution across all views
   - Admin credentials: admin/admin

## Quick Start

### Prerequisites

- Kubernetes cluster (minikube, k3s, or any K8s 1.24+)
- kubectl configured
- Helm 3.x installed
- 8GB RAM, 4 CPU cores recommended

### One-Command Deployment

```bash
./deploy.sh
```

The script will:
1. Clean up any existing resources
2. Deploy the complete stack (Istio + Prometheus + Grafana + Load Generators)
3. Validate metrics collection
4. Prompt to open dashboards automatically

**Duration:** 3-5 minutes

### Manual Deployment

If you prefer step-by-step control:

```bash
# 1. Bootstrap cluster (minikube only)
./scripts/bootstrap-cluster.sh

# 2. Deploy via Helm
helm install proxy-telemetry ./helm/proxy-telemetry -n monitoring --create-namespace --wait

# 3. Validate metrics
./scripts/validate-istio-metrics.sh

# 4. Access dashboards
kubectl port-forward -n monitoring svc/grafana 3000:80 &
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
```

### Access Dashboards

**Grafana:** http://localhost:3000
- Username: `admin`
- Password: `admin`
- Navigate to: **Dashboards → Proxy Telemetry**

**Prometheus:** http://localhost:9090

Available dashboards:
- **Proxy Overview** - Request rates, totals by vendor
- **Bandwidth Analytics** - Bytes sent/received per vendor
- **Destination Tracking** - Top destinations by vendor
- **Performance & Health** - Latency, errors, success rates

## Configuration

### Traffic Generation

Edit `helm/proxy-telemetry/values.yaml`:

```yaml
loadGenerator:
  replicas: 9  # Total pods (3 per vendor for minikube)
  traffic:
    requestsPerSecond: 100  # Per pod
    concurrentRequests: 100
```

Expected traffic: ~900 requests/second total (with 9 pods)

### Resource Allocation

Default per-pod resources:

```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "500m"
  limits:
    memory: "1Gi"
    cpu: "1000m"
```

Total cluster requirement: ~9-12 CPU cores, ~9-12GB RAM

### Proxy Vendors

Configure vendors and traffic distribution:

```yaml
vendors:
  - name: vendor-a
    weight: 40  # 40% of traffic
  - name: vendor-b
    weight: 35  # 35% of traffic
  - name: vendor-c
    weight: 25  # 25% of traffic
```

## Metrics

### Core Metrics

| Metric | Description | Labels |
|--------|-------------|--------|
| `envoy_cluster_upstream_rq_total` | Total requests | proxy_vendor, pod_name, cluster_name, response_code |
| `envoy_cluster_upstream_cx_tx_bytes_total` | Bytes sent (outgoing) | proxy_vendor, pod_name, cluster_name |
| `envoy_cluster_upstream_cx_rx_bytes_total` | Bytes received (incoming) | proxy_vendor, pod_name, cluster_name |

### Example Queries

```promql
# Requirement A: Request rate per vendor
sum by (proxy_vendor) (rate(envoy_cluster_upstream_rq_total[5m]))

# Requirement B: Top destinations
topk(10, sum by (cluster_name, proxy_vendor) (rate(envoy_cluster_upstream_rq_total[5m])))

# Requirement C: Bandwidth sent per vendor per pod
sum by (proxy_vendor, pod_name) (rate(envoy_cluster_upstream_cx_tx_bytes_total[5m]))

# Requirement D: Bandwidth received per vendor per pod
sum by (proxy_vendor, pod_name) (rate(envoy_cluster_upstream_cx_rx_bytes_total[5m]))
```

## Validation

Run comprehensive validation:

```bash
./scripts/validate-istio-metrics.sh
```

Expected output:
```
Requirement A: Request count per proxy vendor
  vendor-a: 1523 requests
  vendor-b: 1401 requests
  vendor-c: 1389 requests
  Status: PASS

Requirement B: Destination tracking
  httpbin.org: 312 requests
  example.com: 245 requests
  Status: PASS

Requirement C: Bandwidth sent (outgoing bytes)
  vendor-a: 245678 bytes
  vendor-b: 198234 bytes
  Status: PASS

Requirement D: Bandwidth received (incoming bytes)
  vendor-a: 1247890 bytes
  vendor-b: 1098765 bytes
  Status: PASS
```

## Scaling

### Horizontal Scaling

Increase number of crawler pods:

```bash
# Scale all vendors
kubectl scale deployment -n crawlers --all --replicas=10

# Scale specific vendor
kubectl scale deployment load-generator-vendor-a -n crawlers --replicas=20
```

### Vertical Scaling

Increase requests per second:

```bash
kubectl set env deployment -n crawlers -l app=load-generator REQUESTS_PER_SECOND=200
```

## Production Deployment

Before deploying to production:

### 1. Update Credentials

```yaml
grafana:
  adminPassword: <secure-password>
```

### 2. Configure Storage

```yaml
prometheus:
  storage:
    volumeSize: 500Gi
    storageClassName: <production-class>
```

### 3. Enable Alerting

Configure Alertmanager endpoints in values.yaml.

### 4. Network Policies

Implement NetworkPolicy resources for namespace isolation.

### 5. Resource Limits

Adjust based on cluster capacity (see [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)).

## Troubleshooting

### No Metrics Appearing

Verify Istio sidecar injection:

```bash
kubectl get namespace crawlers --show-labels
# Should show: istio-injection=enabled

kubectl get pods -n crawlers
# Should show: 2/2 READY (app + istio-proxy)
```

Fix if needed:

```bash
kubectl label namespace crawlers istio-injection=enabled --overwrite
kubectl rollout restart deployment -n crawlers -l app=load-generator
```

### Pods Pending

Check cluster resources:

```bash
kubectl top nodes
```

Reduce replicas if insufficient resources:

```bash
kubectl scale deployment -n crawlers -l app=load-generator --replicas=3
```

### High Error Rates

Check pod logs:

```bash
kubectl logs -n crawlers -l app=load-generator -c load-generator --tail=50
```

Common causes:
- External site rate limiting
- Network connectivity issues
- DNS resolution failures

### View Installation Logs

```bash
# Load generator logs
kubectl logs -n crawlers -l app=load-generator -c load-generator --tail=50

# Istio sidecar logs
kubectl logs -n crawlers -l app=load-generator -c istio-proxy --tail=50
```

## Documentation

- [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) - Complete deployment instructions
- [ARCHITECTURE.md](ARCHITECTURE.md) - Detailed architecture and design decisions
- [DATA-MODEL.md](DATA-MODEL.md) - Metrics schema and query examples
- [PROJECT-STRUCTURE.md](PROJECT-STRUCTURE.md) - Repository organization
- [QUICK-COMMIT-GUIDE.md](QUICK-COMMIT-GUIDE.md) - Git commit strategy

## Technology Stack

- **Service Mesh:** Istio 1.20+
- **Metrics Storage:** Prometheus 2.47+
- **Visualization:** Grafana 10.1+
- **Load Generator:** Python 3.11 with aiohttp
- **Deployment:** Helm 3.x
- **Container Runtime:** Docker/containerd

## Performance Characteristics

| Scale | Crawler Pods | Throughput | Resource Usage |
|-------|-------------|------------|----------------|
| **Development** | 9 | 900 req/s | 4GB RAM, 4 CPU |
| **Production** | 100 | 10K req/s | 16GB RAM, 8 CPU |
| **Enterprise** | 1,000+ | 100K+ req/s | 64GB+ RAM, 32+ CPU |

## Cleanup

```bash
# Remove deployment
helm uninstall proxy-telemetry -n monitoring

# Remove namespaces
kubectl delete namespace monitoring crawlers

# Remove Istio (optional)
istioctl uninstall --purge -y

# Delete cluster (minikube)
minikube delete
```

## Repository Structure

```
.
├── README.md                           # This file
├── ARCHITECTURE.md                     # Architecture deep-dive
├── DATA-MODEL.md                       # Metrics schema and queries
├── DEPLOYMENT-GUIDE.md                 # Production deployment guide
├── deploy.sh                           # Automated deployment script
├── Makefile                            # Build automation
├── helm/proxy-telemetry/               # Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── istio-telemetry.yaml
│   └── templates/
│       ├── namespaces.yaml
│       ├── prometheus-*.yaml
│       ├── grafana-*.yaml
│       ├── load-generator.yaml
│       └── istio-prerequisites-job.yaml
└── scripts/
    ├── bootstrap-cluster.sh            # Cluster setup
    ├── open-dashboards.sh              # Dashboard access
    └── validate-istio-metrics.sh       # Health check
```

## How It Works

### 1. Vendor Attribution

Load generators are labeled with their proxy vendor:

```yaml
metadata:
  labels:
    app: load-generator
    proxy-vendor: vendor-a  # Kubernetes label
```

### 2. Traffic Interception

- Istio automatically injects `istio-proxy` sidecar into crawler pods
- All outbound traffic intercepted via iptables rules
- Works for HTTP, HTTPS, HTTP/1, HTTP/2 without app changes

### 3. Metrics Export

Envoy sidecar exposes metrics on port 15090:

```
envoy_cluster_upstream_rq_total{cluster_name="httpbin.org:443"} 1523
envoy_cluster_upstream_cx_tx_bytes_total{cluster_name="httpbin.org:443"} 245678
```

### 4. Label Enrichment

Prometheus relabeling adds proxy_vendor from pod labels:

```yaml
relabel_configs:
- source_labels: [__meta_kubernetes_pod_label_proxy_vendor]
  target_label: proxy_vendor
```

### 5. Visualization

Grafana dashboards query Prometheus:

```promql
sum by (proxy_vendor) (rate(envoy_cluster_upstream_rq_total[5m]))
```

**Quick Start:** `./deploy.sh` → Answer 'y' to open dashboards → Grafana opens automatically at http://localhost:3000