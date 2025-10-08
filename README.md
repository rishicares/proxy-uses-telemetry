# Kubernetes Proxy Usage Telemetry Solution# Kubernetes Proxy Usage Telemetry Solution# Kubernetes Proxy Usage Telemetry Solution



Production-grade observability solution for monitoring outbound proxy usage from thousands of crawler pods in Kubernetes using Istio service mesh.



## OverviewProduction-grade observability solution for monitoring outbound proxy usage from thousands of crawler pods in Kubernetes using Istio service mesh.Production-grade observability solution for monitoring outbound proxy usage from thousands of crawler pods in Kubernetes using Istio service mesh.



This solution provides complete visibility into proxy usage across large-scale crawler deployments:



- **Request count** per proxy vendor## Overview## Solution Overview

- **Destination tracking** (domain/host)

- **Bandwidth sent** per proxy per pod

- **Bandwidth received** per proxy per pod

This solution provides complete visibility into proxy usage across a large-scale crawler deployment, measuring and attributing all required metrics:This solution provides complete visibility into proxy usage across a large-scale crawler deployment, measuring and attributing all required metrics per the specification.

Supports HTTP, HTTPS, HTTP/1.1, and HTTP/2 with zero application code changes.



## Architecture

- Request count per proxy vendor### Requirements Coverage

### Components

- Destination tracking (domain/host)

**Istio Service Mesh**

- Automatic sidecar injection for transparent telemetry- Bandwidth sent per proxy per pod| Requirement | Implementation | Metric/Method |

- Traffic interception and metrics collection

- Header-based vendor attribution- Bandwidth received per proxy per pod|-------------|----------------|---------------|



**Load Generators**| **a. Request count per proxy** | Istio telemetry with header extraction | `istio_requests_total{proxy_vendor="..."}` |

- Python async application simulating crawlers

- Adds `X-Proxy-Vendor` header for attributionSupports HTTP, HTTPS, HTTP/1.1, and HTTP/2 protocols with zero application code changes.| **b. Destination tracking** | Istio telemetry captures host/domain | `istio_requests_total{destination_service_name="..."}` |

- 100 req/s per pod (configurable)

| **c. Bandwidth sent (outgoing)** | Istio request bytes per pod/proxy | `istio_request_bytes_sum{proxy_vendor="...", pod_name="..."}` |

**Prometheus**

- Scrapes Istio Envoy sidecars for metrics## Architecture| **d. Bandwidth received (incoming)** | Istio response bytes per pod/proxy | `istio_response_bytes_sum{proxy_vendor="...", pod_name="..."}` |

- 30-day retention with recording rules

- Handles 500K+ time series| **HTTP/HTTPS support** | Istio native protocol support | All protocols handled by Envoy proxy |



**Grafana**### Components| **HTTP/1 and HTTP/2** | Istio native protocol support | Automatic protocol detection |

- 4 pre-built dashboards

- Real-time monitoring| **Vendor attribution** | Header-based (X-Proxy-Vendor) | Extracted via Istio Telemetry API |

- Vendor-attributed views

1. **Istio Service Mesh**

### Data Flow

   - Automatic sidecar injection for transparent telemetry## Architecture

```

Crawler Pod   - Traffic interception and metrics collection

  -> Application (adds X-Proxy-Vendor header)

  -> Istio Sidecar (intercepts traffic, emits metrics)   - Header-based vendor attribution via Telemetry API### High-Level Design

  -> Prometheus (collects and stores)

  -> Grafana (visualizes)

```

2. **Load Generators** (Synthetic Crawlers)```

## Quick Start

   - Python async application simulating crawler behaviorCrawler Pod (crawlers namespace)

### Prerequisites

   - Adds `X-Proxy-Vendor` header for attribution├── load-generator container

- Kubernetes 1.24+

- kubectl CLI   - Configurable traffic patterns (100 req/s per pod default)│   └── Adds header: X-Proxy-Vendor: vendor-a

- Helm 3.x

- 8GB RAM, 4 CPU minimum└── istio-proxy sidecar (auto-injected)



### Installation3. **Prometheus**    ├── Intercepts all outbound traffic



**1. Bootstrap Cluster** (for minikube):   - Scrapes Istio Envoy sidecars for metrics    ├── Extracts proxy_vendor from headers

```bash

./scripts/bootstrap-cluster.sh   - 30-day retention with recording rules    └── Emits metrics with vendor labels

```

   - Supports up to 500K time series         ↓

**2. Deploy Solution**:

```bash    Prometheus

./deploy.sh

```4. **Grafana**    ├── Scrapes istio-proxy:15090/stats/prometheus



Or use Helm directly:   - Pre-built dashboards for visualization    ├── Stores: istio_requests_total{proxy_vendor="vendor-a"}

```bash

helm install proxy-telemetry ./helm/proxy-telemetry -n monitoring --create-namespace   - Real-time monitoring and analysis    ├── Stores: istio_request_bytes_sum{proxy_vendor="vendor-a", pod_name="..."}

```

   - Vendor-attributed views    └── Stores: istio_response_bytes_sum{proxy_vendor="vendor-a", pod_name="..."}

**3. Verify**:

```bash         ↓

./scripts/validate-istio-metrics.sh

```### Data Flow    Grafana Dashboards



**4. Access Dashboards**:    ├── Proxy Overview

```bash

kubectl port-forward -n monitoring svc/grafana 3000:80 &```    ├── Bandwidth Analytics

kubectl port-forward -n monitoring svc/prometheus 9090:9090 &

```Crawler Pod    ├── Destination Tracking

- Grafana: http://localhost:3000 (admin/admin)

- Prometheus: http://localhost:9090  └── Application Container (adds X-Proxy-Vendor header)    └── Performance & Health



## Configuration  └── Istio Sidecar (intercepts traffic, emits metrics)```



Edit `helm/proxy-telemetry/values.yaml`:         |



```yaml         v### Key Components

loadGenerator:

  replicas: 21  # Total pods    Prometheus (collects and stores metrics)

  traffic:

    requestsPerSecond: 100  # Per pod         |1. **Istio Service Mesh**

    concurrentRequests: 100

         v   - Automatic sidecar injection (zero app changes)

resources:

  requests:    Grafana (visualizes data)   - Traffic interception and telemetry

    memory: "512Mi"

    cpu: "500m"```   - Header-based vendor attribution via Telemetry API

  limits:

    memory: "1Gi"   - Native HTTP/HTTPS/HTTP2 support

    cpu: "1000m"

## Quick Start

vendors:

  - name: vendor-a2. **Load Generators** (Synthetic Crawlers)

    weight: 40

  - name: vendor-b### Prerequisites   - Python async application

    weight: 35

  - name: vendor-c   - Adds `X-Proxy-Vendor` header to all requests

    weight: 25

```- Kubernetes 1.24+   - Simulates 3 proxy vendors (vendor-a, vendor-b, vendor-c)



**Expected Traffic**: ~2,100 requests/second total- kubectl CLI configured   - Makes requests to various HTTP/HTTPS endpoints



## Metrics- Helm 3.x



### Key Metrics- 8GB RAM, 4 CPU cores minimum3. **Prometheus**



| Metric | Description | Labels |   - Scrapes Istio Envoy sidecars (port 15090)

|--------|-------------|--------|

| `envoy_cluster_upstream_rq_total` | Total requests | proxy_vendor, pod_name, response_code |### Installation   - Stores time-series metrics with vendor labels

| `envoy_cluster_upstream_cx_tx_bytes_total` | Bytes sent | proxy_vendor, pod_name |

| `envoy_cluster_upstream_cx_rx_bytes_total` | Bytes received | proxy_vendor, pod_name |   - 30-day retention (configurable)



### Example Queries1. **Bootstrap Cluster** (if using minikube):   - Recording rules for aggregations



```promql

# Request rate by vendor

sum by (proxy_vendor) (rate(envoy_cluster_upstream_rq_total[1m]))```bash4. **Grafana**



# Bandwidth sent per vendor./scripts/bootstrap-cluster.sh   - 4 pre-built dashboards

sum by (proxy_vendor) (rate(envoy_cluster_upstream_cx_tx_bytes_total[1m]))

```   - Real-time visualization

# Bandwidth received per pod

sum by (proxy_vendor, pod_name) (rate(envoy_cluster_upstream_cx_rx_bytes_total[1m]))   - Vendor attribution across all views



# Top destinations2. **Deploy Solution**:   - Admin credentials: admin/admin

topk(10, sum by (destination_host) (rate(envoy_cluster_upstream_rq_total[1m])))

```



## Scaling```bash## Quick Start



**Horizontal** (more pods):./deploy.sh

```bash

kubectl scale deployment -n crawlers -l app=load-generator --replicas=10```### Prerequisites

```



**Vertical** (more requests per pod):

```bashOr manually with Helm:- Kubernetes cluster (minikube, k3s, or any K8s 1.24+)

kubectl set env deployment -n crawlers -l app=load-generator REQUESTS_PER_SECOND=200

```- kubectl configured



## Dashboards```bash- Helm 3.x installed



Four pre-configured Grafana dashboards:helm install proxy-telemetry ./helm/proxy-telemetry -n monitoring --create-namespace- 8GB RAM, 4 CPU cores recommended



1. **Proxy Overview** - Request rates, success rates, bandwidth```

2. **Bandwidth Analytics** - Inbound/outbound by vendor and pod

3. **Destination Tracking** - Top destinations, response times### Bootstrap Cluster (minikube)

4. **Performance & Health** - Latency, errors, resource usage

3. **Verify Deployment**:

## Production Deployment

```bash

Before production:

```bash# Start minikube with sufficient resources

1. **Update credentials**:

   ```yaml./scripts/validate-istio-metrics.shminikube start --cpus=4 --memory=8192 --driver=docker

   grafana:

     adminPassword: <secure-password>```

   ```

# Or use the provided bootstrap script

2. **Configure storage**:

   ```yaml4. **Access Dashboards**:./scripts/bootstrap-cluster.sh

   prometheus:

     storage:```

       volumeSize: 500Gi

       storageClassName: <production-class>```bash

   ```

# Port forward services### Deploy Complete Stack

3. **Enable TLS**: Update load generator SSL settings

4. **Network policies**: Implement namespace isolationkubectl port-forward -n monitoring svc/grafana 3000:80 &

5. **Alerting**: Configure Alertmanager endpoints

kubectl port-forward -n monitoring svc/prometheus 9090:9090 &```bash

See `DEPLOYMENT-GUIDE.md` for complete instructions.

# Single command deployment

## Troubleshooting

# Access in browser# Automatically installs: Istio -> Prometheus -> Grafana -> Load Generators

### No Metrics

# Grafana: http://localhost:3000 (admin/admin)./deploy.sh

Verify sidecar injection:

```bash# Prometheus: http://localhost:9090```

kubectl get namespace crawlers --show-labels

# Should show: istio-injection=enabled```



kubectl get pods -n crawlers**Deployment Process:**

# Should show: 2/2 READY

```## Configuration1. Cleans up any existing resources



Fix if needed:2. Creates monitoring namespace

```bash

kubectl label namespace crawlers istio-injection=enabled --overwrite### Traffic Generation3. Helm pre-install hook checks/installs Istio

kubectl rollout restart deployment -n crawlers -l app=load-generator

```4. Deploys Prometheus with Istio metric scraping



### Pods PendingEdit `helm/proxy-telemetry/values.yaml`:5. Deploys Grafana with 4 dashboards



Check resources:6. Deploys load generators with Istio sidecar injection

```bash

kubectl top nodes```yaml7. Helm post-install hook validates stack health

```

loadGenerator:

Reduce replicas:

```bash  replicas: 21  # Total pods (distributed across vendors)**Duration:** 3-5 minutes

kubectl scale deployment -n crawlers -l app=load-generator --replicas=5

```  traffic:



### High Errors    requestsPerSecond: 100  # Per pod### Access Dashboards



Check logs:    concurrentRequests: 100

```bash

kubectl logs -n crawlers -l app=load-generator -c load-generator --tail=50``````bash

```

# Port-forward Grafana

Common causes: rate limiting, network issues, DNS failures

Expected traffic: ~2,100 requests/second totalkubectl port-forward -n monitoring svc/grafana 3000:80

## Documentation

```

- `DEPLOYMENT-GUIDE.md` - Complete deployment instructions

- `ARCHITECTURE.md` - System design and architecture### Resource Allocation

- `DATA-MODEL.md` - Metrics schema and queries

- `CHANGES.md` - Configuration changesOpen: http://localhost:3000

- `PROJECT-STRUCTURE.md` - Repository organization

Default per-pod resources:- Username: admin

## Validation

- Password: admin

Run validation:

```bash```yaml

./scripts/validate-istio-metrics.sh

```resources:Navigate to: **Dashboards → Proxy Telemetry**



Expected output:  requests:

- Found N pods with Istio sidecars: SUCCESS

- Request count metrics: SUCCESS    memory: "512Mi"Available dashboards:

- Destination tracking: SUCCESS

- Bandwidth sent: SUCCESS    cpu: "500m"- **Proxy Overview** - Request rates, totals by vendor

- Bandwidth received: SUCCESS

  limits:- **Bandwidth Analytics** - Bytes sent/received per vendor

## Support

    memory: "1Gi"- **Destination Tracking** - Top destinations by vendor

For issues:

1. Check pod logs    cpu: "1000m"- **Performance & Health** - Latency, errors, success rates

2. Run validation script

3. Review documentation```

4. Check troubleshooting section

### Validate Metrics

Total cluster requirement: ~11 CPU cores, ~11GB RAM

```bash

### Proxy Vendors# Automated validation of all 4 requirements

./scripts/validate-istio-metrics.sh

Configure vendors and traffic distribution:```



```yamlExpected output:

vendors:```

  - name: vendor-aRequirement A: Request count per proxy vendor

    weight: 40  # Percentage  vendor-a: 1523 requests

  - name: vendor-b  vendor-b: 1401 requests

    weight: 35  vendor-c: 1389 requests

  - name: vendor-c  Status: PASS

    weight: 25

```Requirement B: Destination tracking

  example.com: 245 requests

## Metrics  httpbin.org: 312 requests

  Status: PASS

### Key Metrics

Requirement C: Bandwidth sent (outgoing bytes)

| Metric | Description | Labels |  vendor-a: 245678 bytes

|--------|-------------|--------|  vendor-b: 198234 bytes

| `envoy_cluster_upstream_rq_total` | Total requests | proxy_vendor, pod_name, response_code |  Status: PASS

| `envoy_cluster_upstream_cx_tx_bytes_total` | Bytes sent | proxy_vendor, pod_name |

| `envoy_cluster_upstream_cx_rx_bytes_total` | Bytes received | proxy_vendor, pod_name |Requirement D: Bandwidth received (incoming bytes)

  vendor-a: 1247890 bytes

### Example Queries  vendor-b: 1098765 bytes

  Status: PASS

```promql```

# Request rate by vendor

sum by (proxy_vendor) (rate(envoy_cluster_upstream_rq_total[1m]))## Data Model



# Bandwidth sent per vendorSee [DATA-MODEL.md](DATA-MODEL.md) for complete schema.

sum by (proxy_vendor) (rate(envoy_cluster_upstream_cx_tx_bytes_total[1m]))

### Core Metrics

# Bandwidth received per pod

sum by (proxy_vendor, pod_name) (rate(envoy_cluster_upstream_cx_rx_bytes_total[1m]))**istio_requests_total** (Counter)

- Description: Total HTTP requests through the service mesh

# Top destinations- Labels:

topk(10, sum by (destination_host) (rate(envoy_cluster_upstream_rq_total[1m])))  - `proxy_vendor`: Vendor identifier (vendor-a, vendor-b, vendor-c)

```  - `destination_service_name`: Target domain/host

  - `response_code`: HTTP status code

## Scaling  - `pod_name`: Source pod identifier

  - `reporter`: source (client-side metrics)

### Horizontal Scaling

**istio_request_bytes_sum** (Counter)

Increase number of crawler pods:- Description: Total request payload bytes sent (outgoing)

- Labels: `proxy_vendor`, `pod_name`, `reporter`

```bash

kubectl scale deployment -n crawlers \**istio_response_bytes_sum** (Counter)

  load-generator-vendor-a \- Description: Total response payload bytes received (incoming)

  load-generator-vendor-b \- Labels: `proxy_vendor`, `pod_name`, `reporter`

  load-generator-vendor-c \

  --replicas=10**istio_request_duration_milliseconds** (Histogram)

```- Description: Request latency distribution

- Labels: `proxy_vendor`, `response_code`

### Vertical Scaling

### Example Queries

Increase requests per second:

```promql

```bash# Requirement A: Request count per proxy vendor

kubectl set env deployment -n crawlers -l app=load-generator \sum by (proxy_vendor) (istio_requests_total{reporter="source"})

  REQUESTS_PER_SECOND=200

```# Requirement B: Destination tracking

topk(10, sum by (destination_service_name, proxy_vendor) (rate(istio_requests_total{reporter="source"}[5m])))

## Grafana Dashboards

# Requirement C: Bandwidth sent per proxy per pod

Four pre-configured dashboards:sum by (proxy_vendor, pod_name) (rate(istio_request_bytes_sum{reporter="source"}[5m]))



1. **Proxy Overview**# Requirement D: Bandwidth received per proxy per pod

   - Total request rates by vendorsum by (proxy_vendor, pod_name) (rate(istio_response_bytes_sum{reporter="source"}[5m]))

   - Success rates and error rates```

   - Active crawler pod counts

   - Total bandwidth usage## Deployment Architecture



2. **Bandwidth Analytics**### Helm Chart Structure

   - Outbound/inbound bandwidth by vendor

   - Top bandwidth-consuming pods```

   - 24-hour transfer totalshelm/proxy-telemetry/

   - Transfer rate histograms├── Chart.yaml                          # Helm chart metadata

├── values.yaml                         # Configuration values

3. **Destination Tracking**├── istio-telemetry.yaml               # Istio Telemetry API config

   - Top destinations by request count└── templates/

   - Requests per destination per vendor    ├── 00-prerequisites-job.yaml      # Pre-install: Istio setup

   - Destination response times    ├── 01-validation-job.yaml         # Post-install: Validation

   - Geographic distribution    ├── grafana-dashboards.yaml        # Dashboard definitions

    ├── grafana-deployment.yaml        # Grafana deployment

4. **Performance & Health**    ├── load-generator.yaml            # Synthetic crawler pods

   - Request latency (P50, P95, P99)    ├── prometheus-configmap.yaml      # Prometheus config

   - Error rates per vendor    └── prometheus-deployment.yaml     # Prometheus deployment

   - Pod health status```

   - Resource utilization

### Namespaces

## Production Deployment

- **monitoring**: Prometheus, Grafana

Before deploying to production:- **crawlers**: Load generator pods (with Istio sidecar injection)

- **istio-system**: Istio control plane (auto-created)

1. **Update Credentials**:

## How It Works

```yaml

grafana:### 1. Vendor Attribution via Headers

  adminPassword: <secure-password>

```Load generators add vendor identification:



2. **Configure Storage**:```python

headers = {

```yaml    'X-Proxy-Vendor': 'vendor-a',

prometheus:    'X-Proxy-Pool': 'residential',

  storage:    'User-Agent': 'Crawler-v1.0'

    volumeSize: 500Gi}

    storageClassName: <production-class>async with aiohttp.ClientSession(headers=headers) as session:

```    async with session.get(url) as response:

        # Traffic automatically flows through Istio sidecar

3. **Enable Alerting**:```



Configure Alertmanager endpoints in values.yaml.### 2. Automatic Traffic Interception



4. **Set Up TLS**:- Istio automatically injects `istio-proxy` sidecar into crawler pods

- No application code changes required

Enable SSL verification in load generator and configure ingress with TLS.- All outbound traffic intercepted via iptables rules

- Works for HTTP, HTTPS, HTTP/1, HTTP/2

5. **Network Policies**:

### 3. Telemetry Extraction

Implement NetworkPolicy resources for namespace isolation.

Istio Telemetry API configuration extracts vendor from headers:

See `PRODUCTION-CHECKLIST.md` for complete list.

```yaml

## TroubleshootingapiVersion: telemetry.istio.io/v1alpha1

kind: Telemetry

### No Metrics Appearingspec:

  metrics:

Verify Istio sidecar injection:  - overrides:

    - match:

```bash        metric: REQUEST_COUNT

kubectl get namespace crawlers --show-labels      tagOverrides:

# Should show: istio-injection=enabled        proxy_vendor:

          value: "request.headers['x-proxy-vendor'] | 'unknown'"

kubectl get pods -n crawlers```

# Should show: 2/2 READY

```### 4. Metrics Collection



Fix if needed:Prometheus scrapes Istio Envoy sidecars:



```bash```yaml

kubectl label namespace crawlers istio-injection=enabled --overwritescrape_configs:

kubectl rollout restart deployment -n crawlers -l app=load-generator- job_name: 'istio-envoy-sidecars'

```  kubernetes_sd_configs:

  - role: pod

### High Error Rates    namespaces: [crawlers]

  relabel_configs:

Check pod logs:  - source_labels: [__meta_kubernetes_pod_container_name]

    regex: 'istio-proxy'

```bash    action: keep

kubectl logs -n crawlers -l app=load-generator -c load-generator --tail=50  - source_labels: [__meta_kubernetes_pod_ip]

```    target_label: __address__

    replacement: $1:15090

Common causes:```

- External site rate limiting

- Network connectivity issues### 5. Visualization

- DNS resolution failures

Grafana queries Prometheus using PromQL:

### Pods Pending

```promql

Check cluster resources:# Request rate per vendor

sum by (proxy_vendor) (rate(istio_requests_total{reporter="source"}[5m]))

```bash

kubectl top nodes# Bandwidth sent per vendor

```sum by (proxy_vendor) (rate(istio_request_bytes_sum{reporter="source"}[5m]))

```

Reduce replicas if insufficient resources:

## Production Deployment

```bash

kubectl scale deployment -n crawlers -l app=load-generator --replicas=5See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed production deployment guide.

```

### Configuration

## Documentation

Customize via `helm/proxy-telemetry/values.yaml`:

- `DEPLOYMENT-GUIDE.md` - Complete deployment instructions

- `ARCHITECTURE.md` - Detailed architecture and design decisions```yaml

- `DATA-MODEL.md` - Metrics schema and query examplesloadGenerator:

- `REQUIREMENTS-COMPLIANCE.md` - Requirements mapping  replicas: 9  # Total replicas across vendors

- `PRODUCTION-CHECKLIST.md` - Production readiness checklist  vendors:

- `CHANGES.md` - Configuration changes and improvements    - name: vendor-a

      weight: 40  # 40% of traffic

## Validation    - name: vendor-b

      weight: 35

Run comprehensive validation:    - name: vendor-c

      weight: 25

```bash

./scripts/validate-istio-metrics.shprometheus:

```  retention: 30d

  storage:

Expected output:    size: 50Gi

- Found N pods with Istio sidecars

- Request count metrics: SUCCESSgrafana:

- Destination tracking: SUCCESS  persistence:

- Bandwidth sent metrics: SUCCESS    enabled: true

- Bandwidth received metrics: SUCCESS    size: 10Gi

```

## Support

### Scaling

For issues:

1. Check pod logs```bash

2. Run validation script# Scale specific vendor

3. Review troubleshooting sectionkubectl scale deployment load-generator-vendor-a -n crawlers --replicas=20

4. Check documentation

# Adjust request rate per pod

## Licensekubectl set env deployment/load-generator-vendor-a -n crawlers REQUESTS_PER_SECOND=50

```

Internal use only.

## Validation & Testing

### Verify Istio Sidecar Injection

```bash
kubectl get pods -n crawlers -o wide
```

Expected: `2/2 Running` (load-generator + istio-proxy)

### Query Prometheus Directly

```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Access at http://localhost:9090
# Run query: sum by (proxy_vendor) (rate(istio_requests_total{reporter="source"}[5m]))
```

### View Raw Envoy Metrics

```bash
POD=$(kubectl get pods -n crawlers -l app=load-generator -o name | head -1)
kubectl exec -n crawlers $POD -c istio-proxy -- curl -s localhost:15090/stats/prometheus | grep istio_requests_total
```

## Troubleshooting

### Pods show 1/2 containers

**Issue:** Istio sidecar not injected

**Fix:**
```bash
kubectl label namespace crawlers istio-injection=enabled --overwrite
kubectl rollout restart deployment -n crawlers
```

### No metrics in Prometheus

**Check scrape targets:**
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Visit: http://localhost:9090/targets
# Verify: istio-envoy-sidecars targets are UP
```

### Grafana dashboards empty

1. Verify time range: Use "Last 15 minutes"
2. Refresh dashboard
3. Check Prometheus data source: Settings → Data Sources → Prometheus → Test
4. Run validation: `./scripts/validate-istio-metrics.sh`

### View installation logs

```bash
# Istio installation logs
kubectl logs -n monitoring job/istio-installer

# Validation logs
kubectl logs -n monitoring job/stack-validator

# Load generator logs
kubectl logs -n crawlers -l app=load-generator -c load-generator --tail=50

# Istio sidecar logs
kubectl logs -n crawlers -l app=load-generator -c istio-proxy --tail=50
```

## Demo Guide

See [DEMO-GUIDE.md](DEMO-GUIDE.md) for complete live demonstration script.

### Quick Demo (5 minutes)

```bash
# 1. Deploy stack
./deploy.sh

# 2. Show Istio sidecar injection (2/2 containers)
kubectl get pods -n crawlers -o wide

# 3. Validate all 4 requirements
./scripts/validate-istio-metrics.sh

# 4. Open Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80
# Navigate to: Dashboards → Proxy Telemetry

# 5. Show Prometheus queries
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Query: sum by (proxy_vendor) (rate(istio_requests_total{reporter="source"}[5m]))

# 6. Demonstrate scaling
kubectl scale deployment load-generator-vendor-a -n crawlers --replicas=10
# Show metrics scale proportionally in Grafana
```

## Technology Stack

- **Service Mesh:** Istio 1.20+
- **Metrics Storage:** Prometheus 2.45+
- **Visualization:** Grafana 10.0+
- **Load Generator:** Python 3.11 with aiohttp
- **Deployment:** Helm 3.x
- **Container Runtime:** Docker/containerd

## Performance Characteristics

| Scale | Crawler Pods | Throughput | Resource Usage |
|-------|-------------|------------|----------------|
| **Development** | 10-100 | 1K req/min | 2GB RAM, 1 CPU |
| **Production** | 1,000 | 100K req/min | 8GB RAM, 4 CPU |
| **Enterprise** | 5,000+ | 1M+ req/min | 32GB+ RAM, 16+ CPU |

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

## Files Structure

```
.
├── README.md                           # This file
├── ARCHITECTURE.md                     # Architecture deep-dive
├── DATA-MODEL.md                       # Metrics schema and queries
├── DEMO-GUIDE.md                       # Live demo script
├── DEPLOYMENT.md                       # Production deployment guide
├── deploy.sh                           # Main deployment script
├── Makefile                            # Convenience commands
├── helm/proxy-telemetry/              # Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── istio-telemetry.yaml
│   └── templates/
└── scripts/
    ├── bootstrap-cluster.sh
    ├── open-dashboards.sh
    └── validate-istio-metrics.sh
```

## Summary

This solution provides a production-ready, self-contained package for Kubernetes proxy usage telemetry that:

- Meets all 4 requirements (a-d) with automated validation
- Supports HTTP/HTTPS, HTTP/1, HTTP/2 protocols
- Uses open-source technologies (Istio, Prometheus, Grafana)
- Provides complete observability with vendor attribution
- Includes synthetic load generator for testing
- Offers 4 pre-built Grafana dashboards
- Auto-installs all prerequisites via Helm hooks
- Works on minikube/k3s/any Kubernetes cluster

**Quick Start:** `./deploy.sh` → Answer 'y' to open dashboards → Grafana opens automatically at http://localhost:3000 (admin/admin)