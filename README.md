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
| **a. Request count per proxy** | Istio telemetry with header extraction | `istio_requests_total{proxy_vendor="..."}` |
| **b. Destination tracking** | Istio telemetry metrics | `destination_host` label contains destination |
| **c. Bandwidth sent (outgoing)** | Istio telemetry metrics | `istio_request_bytes_sent` |
| **d. Bandwidth received (incoming)** | Istio telemetry metrics | `istio_response_bytes_received` |
| **HTTP/HTTPS support** | Istio native protocol support | All protocols handled by Envoy proxy |
| **HTTP/1 and HTTP/2** | Istio native protocol support | Automatic protocol detection |
| **Vendor attribution** | Istio telemetry header extraction | Extracted from X-Proxy-Vendor header |

## Architecture

### High-Level Design

```
Crawler Pod (crawlers namespace)
├── load-generator container
│   └── Adds header: X-Proxy-Vendor: vendor-a
└── istio-proxy sidecar (auto-injected by Istio)
    ├── Intercepts all outbound traffic via Istio
    ├── Exposes metrics on port 15090
    └── Istio telemetry extracts vendor from headers
         ↓
    Prometheus (monitoring namespace)
    ├── Scrapes istio-proxy:15090/stats/prometheus
    ├── Relabels metrics with proxy_vendor from Istio telemetry
    └── Stores: istio_requests_total{proxy_vendor="vendor-a"}
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
- Sufficient resources for your deployment scale

### One-Command Deployment

```bash
./deploy.sh
```

The script will:
1. Clean up any existing resources
2. Deploy the complete stack (Istio + Prometheus + Grafana + Load Generators)
3. Validate metrics collection
4. Prompt to open dashboards automatically

**Duration:** Depends on cluster resources and network speed

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

Traffic generation configurable via values.yaml

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

Resource requirements depend on replica count and traffic configuration

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
| `istio_requests_total` | Total requests | proxy_vendor, pod_name, destination_host, response_code |
| `istio_request_bytes_sent` | Bytes sent (outgoing) | proxy_vendor, pod_name, destination_host |
| `istio_response_bytes_received` | Bytes received (incoming) | proxy_vendor, pod_name, destination_host |

### Example Queries

```promql
# Requirement A: Request rate per vendor
sum by (proxy_vendor) (rate(istio_requests_total[5m]))

# Requirement B: Top destinations
topk(10, sum by (destination_host, proxy_vendor) (rate(istio_requests_total[5m])))

# Requirement C: Bandwidth sent per vendor per pod
sum by (proxy_vendor, pod_name) (rate(istio_request_bytes_sent[5m]))

# Requirement D: Bandwidth received per vendor per pod
sum by (proxy_vendor, pod_name) (rate(istio_response_bytes_received[5m]))
```

## Validation

Run comprehensive validation:

```bash
./scripts/validate-istio-metrics.sh
```

The validation script checks all four requirements and reports PASS/FAIL status for each.

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

## Technology Stack

- **Service Mesh:** Istio 1.20+
- **Metrics Storage:** Prometheus 2.47+
- **Visualization:** Grafana 10.1+
- **Load Generator:** Python 3.11 with aiohttp
- **Deployment:** Helm 3.x
- **Container Runtime:** Docker/containerd

## Performance Characteristics

Performance depends on cluster resources, replica count, and traffic configuration. Adjust resources and replicas based on your requirements.

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

Load generators add X-Proxy-Vendor header to requests, which Istio telemetry extracts.

### 2. Traffic Interception

- Istio automatically injects `istio-proxy` sidecar into crawler pods
- All outbound traffic intercepted via Istio service mesh
- Works for HTTP, HTTPS, HTTP/1, HTTP/2 without app changes

### 3. Metrics Export

Istio sidecar exposes metrics on port 15090 with telemetry-extracted labels.

### 4. Label Enrichment

Istio telemetry API extracts proxy_vendor from X-Proxy-Vendor header and adds it to metrics.

### 5. Visualization

Grafana dashboards query Prometheus using Istio metrics:

```promql
sum by (proxy_vendor) (rate(istio_requests_total[5m]))
```

**Quick Start:** `./deploy.sh` → Answer 'y' to open dashboards → Grafana opens automatically at http://localhost:3000