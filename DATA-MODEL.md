# Data Model & Metrics Schema

## Overview

This document defines the complete data model for proxy usage telemetry, including metric names, label schemas, cardinality analysis, and query patterns.

## Core Metrics

### 1. Request Metrics

#### `envoy_cluster_upstream_rq_total`
**Description**: Total count of requests sent through proxies

**Type**: Counter

**Labels**:
```yaml
proxy_vendor: string        # Proxy vendor identifier (vendor-a, vendor-b, vendor-c)
pod_name: string           # Kubernetes pod name
namespace: string          # Always "crawlers"
cluster_name: string       # Envoy cluster name (passthrough)
response_code: string      # HTTP response code (200, 404, 500, etc.)
response_code_class: string # Response class (2xx, 4xx, 5xx)
destination_host: string   # Target hostname (HTTP only)
destination_ip: string     # Target IP address
```

**Usage Examples**:
```promql
# Requirement A: Requests per vendor
sum by (proxy_vendor) (rate(envoy_cluster_upstream_rq_total[5m]))

# Requests by vendor and response code
sum by (proxy_vendor, response_code_class) (rate(envoy_cluster_upstream_rq_total[5m]))

# Top pods by request count
topk(10, sum by (pod_name, proxy_vendor) (rate(envoy_cluster_upstream_rq_total[5m])))
```

**Cardinality Estimate**:
- Vendors: 3-10
- Pods: 100-5000
- Response codes: ~20
- Destinations: 1000-10000
- **Total series**: ~50K-500K

### 2. Bandwidth Metrics

#### `envoy_cluster_upstream_cx_tx_bytes_total`
**Description**: Total bytes sent (outgoing) through proxy connections

**Type**: Counter

**Labels**:
```yaml
proxy_vendor: string
pod_name: string
namespace: string
cluster_name: string
```

**Usage Examples**:
```promql
# Requirement C: Bandwidth sent per proxy per pod
sum by (proxy_vendor, pod_name) (rate(envoy_cluster_upstream_cx_tx_bytes_total[5m]))

# Total outbound bandwidth by vendor
sum by (proxy_vendor) (rate(envoy_cluster_upstream_cx_tx_bytes_total[5m]))

# Top bandwidth consumers
topk(20, rate(envoy_cluster_upstream_cx_tx_bytes_total[5m]))
```

**Cardinality Estimate**:
- Vendors: 3-10
- Pods: 100-5000
- **Total series**: ~300-50K

#### `envoy_cluster_upstream_cx_rx_bytes_total`
**Description**: Total bytes received (incoming) through proxy connections

**Type**: Counter

**Labels**: Same as `envoy_cluster_upstream_cx_tx_bytes_total`

**Usage Examples**:
```promql
# Requirement D: Bandwidth received per proxy per pod
sum by (proxy_vendor, pod_name) (rate(envoy_cluster_upstream_cx_rx_bytes_total[5m]))

# Data transfer ratio (sent/received)
sum by (proxy_vendor) (rate(envoy_cluster_upstream_cx_tx_bytes_total[5m])) /
sum by (proxy_vendor) (rate(envoy_cluster_upstream_cx_rx_bytes_total[5m]))
```

### 3. Destination Tracking

#### `envoy_cluster_external_upstream_rq`
**Description**: Requests grouped by destination host

**Type**: Counter

**Labels**:
```yaml
proxy_vendor: string
destination_host: string    # Extracted from HTTP Host header
destination_port: string    # Target port (80, 443, etc.)
destination_ip: string      # Resolved IP address
```

**Usage Examples**:
```promql
# Requirement B: Top destinations by vendor
topk(50, sum by (destination_host, proxy_vendor) (rate(envoy_cluster_external_upstream_rq[5m])))

# Unique destinations per vendor
count by (proxy_vendor) (envoy_cluster_external_upstream_rq)

# Geographic destination analysis (with GeoIP)
sum by (proxy_vendor, destination_country) (rate(envoy_cluster_external_upstream_rq[5m]))
```

**Cardinality Estimate**:
- Destinations: 1000-100K
- Vendors: 3-10
- **Total series**: ~3K-1M

### 4. Latency Metrics

#### `envoy_cluster_upstream_rq_time`
**Description**: Request duration histogram

**Type**: Histogram

**Labels**:
```yaml
proxy_vendor: string
pod_name: string
cluster_name: string
```

**Buckets**: [10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s, +Inf]

**Usage Examples**:
```promql
# P99 latency by vendor
histogram_quantile(0.99, 
  sum by (proxy_vendor, le) (rate(envoy_cluster_upstream_rq_time_bucket[5m]))
)

# Average latency
sum by (proxy_vendor) (rate(envoy_cluster_upstream_rq_time_sum[5m])) /
sum by (proxy_vendor) (rate(envoy_cluster_upstream_rq_time_count[5m]))
```

### 5. Connection Metrics

#### `envoy_cluster_upstream_cx_total`
**Description**: Total connections established

**Type**: Counter

**Labels**: Standard labels (proxy_vendor, pod_name, cluster_name)

#### `envoy_cluster_upstream_cx_active`
**Description**: Currently active connections

**Type**: Gauge

**Labels**: Standard labels

**Usage Examples**:
```promql
# Connection churn rate
rate(envoy_cluster_upstream_cx_total[5m])

# Connection pool utilization
envoy_cluster_upstream_cx_active / envoy_cluster_upstream_cx_pool_total
```

## Label Cardinality Analysis

### High Cardinality Labels
**[WARNING] Requires careful monitoring**

| Label | Cardinality | Notes |
|-------|-------------|-------|
| `pod_name` | 100-5000 | Scales with crawler deployment |
| `destination_host` | 1000-100K | Depends on crawling scope |
| `destination_ip` | 5000-1M | Many IPs per host |
| `response_code` | ~60 | All HTTP status codes |

### Low Cardinality Labels
**[SAFE] Safe for aggregation**

| Label | Cardinality | Notes |
|-------|-------------|-------|
| `proxy_vendor` | 3-10 | Fixed vendor list |
| `namespace` | 1 | Always "crawlers" |
| `response_code_class` | 5 | 1xx, 2xx, 3xx, 4xx, 5xx |
| `cluster_name` | 1-3 | Envoy cluster config |

### Cardinality Optimization Strategies

1. **Drop high-cardinality labels in recording rules**:
```yaml
- record: proxy:request_rate:vendor
  expr: sum by (proxy_vendor) (rate(envoy_cluster_upstream_rq_total[5m]))
  # Drops pod_name, destination_host, etc.
```

2. **Use metric relabeling to limit destination cardinality**:
```yaml
metric_relabel_configs:
  - source_labels: [destination_host]
    regex: '(.{100}).*'
    target_label: destination_host
    replacement: '${1}...'  # Truncate long hosts
```

3. **Aggregate by domain instead of full host**:
```promql
# Extract TLD from full hostname
label_replace(
  envoy_cluster_upstream_rq_total,
  "destination_domain",
  "$1",
  "destination_host",
  ".*\\.([^.]+\\.[^.]+)$"
)
```

## Prometheus Recording Rules

### Pre-aggregated Metrics for Performance

```yaml
groups:
  - name: proxy_telemetry_recording_rules
    interval: 15s
    rules:
      # Request rates by vendor
      - record: proxy:requests_per_second:vendor
        expr: sum by (proxy_vendor) (rate(envoy_cluster_upstream_rq_total[5m]))
      
      # Bandwidth by vendor (bytes/sec)
      - record: proxy:bandwidth_out_bytes_per_second:vendor
        expr: sum by (proxy_vendor) (rate(envoy_cluster_upstream_cx_tx_bytes_total[5m]))
      
      - record: proxy:bandwidth_in_bytes_per_second:vendor
        expr: sum by (proxy_vendor) (rate(envoy_cluster_upstream_cx_rx_bytes_total[5m]))
      
      # Error rate by vendor
      - record: proxy:error_rate:vendor
        expr: |
          sum by (proxy_vendor) (rate(envoy_cluster_upstream_rq_total{response_code_class=~"4xx|5xx"}[5m])) /
          sum by (proxy_vendor) (rate(envoy_cluster_upstream_rq_total[5m]))
      
      # Top destinations per vendor (limited to top 100)
      - record: proxy:top_destinations:vendor
        expr: |
          topk(100, 
            sum by (proxy_vendor, destination_host) (rate(envoy_cluster_upstream_rq_total[5m]))
          )
      
      # Per-pod bandwidth (for granular analysis)
      - record: proxy:bandwidth_per_pod:vendor_pod
        expr: |
          sum by (proxy_vendor, pod_name) (
            rate(envoy_cluster_upstream_cx_tx_bytes_total[5m]) +
            rate(envoy_cluster_upstream_cx_rx_bytes_total[5m])
          )
      
      # Latency percentiles
      - record: proxy:request_duration_p99:vendor
        expr: |
          histogram_quantile(0.99,
            sum by (proxy_vendor, le) (rate(envoy_cluster_upstream_rq_time_bucket[5m]))
          )
      
      - record: proxy:request_duration_p95:vendor
        expr: |
          histogram_quantile(0.95,
            sum by (proxy_vendor, le) (rate(envoy_cluster_upstream_rq_time_bucket[5m]))
          )
```

## Query Patterns for Dashboards

### Dashboard 1: Proxy Overview

```promql
# Total requests per vendor (gauge)
sum by (proxy_vendor) (increase(envoy_cluster_upstream_rq_total[1h]))

# Request rate trend (graph)
proxy:requests_per_second:vendor

# Active crawler pods (gauge)
count by (proxy_vendor) (
  count by (pod_name, proxy_vendor) (envoy_cluster_upstream_rq_total)
)

# Success rate (gauge)
1 - proxy:error_rate:vendor
```

### Dashboard 2: Bandwidth Analytics

```promql
# Outbound bandwidth per vendor (graph)
proxy:bandwidth_out_bytes_per_second:vendor

# Inbound bandwidth per vendor (graph)
proxy:bandwidth_in_bytes_per_second:vendor

# Top bandwidth consumers (table)
topk(20, proxy:bandwidth_per_pod:vendor_pod)

# Total data transfer (stat)
sum(increase(envoy_cluster_upstream_cx_tx_bytes_total[24h])) +
sum(increase(envoy_cluster_upstream_cx_rx_bytes_total[24h]))
```

### Dashboard 3: Destination Analysis

```promql
# Top destinations (table)
proxy:top_destinations:vendor

# Request distribution by destination (pie chart)
sum by (destination_host) (rate(envoy_cluster_upstream_rq_total[1h]))

# Unique destinations per vendor (stat)
count by (proxy_vendor) (
  count by (proxy_vendor, destination_host) (envoy_cluster_upstream_rq_total)
)
```

### Dashboard 4: Performance & Health

```promql
# P99 latency by vendor (graph)
proxy:request_duration_p99:vendor

# Error rate by vendor (graph)
proxy:error_rate:vendor * 100

# Connection pool health (graph)
envoy_cluster_upstream_cx_active / envoy_cluster_max_connections

# Request success rate by response code (stacked area)
sum by (proxy_vendor, response_code_class) (rate(envoy_cluster_upstream_rq_total[5m]))
```

## Data Retention Strategy

### Prometheus Configuration

```yaml
# Short-term high-resolution data
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# Retention policy
storage:
  tsdb:
    retention.time: 30d
    retention.size: 50GB
```

### Long-term Storage (Optional)

For retention > 30 days, use **Thanos** or **Cortex**:

```yaml
# Thanos sidecar configuration
thanos:
  enabled: true
  objectStorageConfig:
    bucket: proxy-telemetry-metrics
    endpoint: s3.amazonaws.com
  retention: 2y  # Long-term storage
```

## Cost Attribution Model

### Bandwidth-based Cost Calculation

```promql
# Estimated cost per vendor (assuming $0.10/GB)
(
  sum by (proxy_vendor) (increase(envoy_cluster_upstream_cx_tx_bytes_total[30d])) +
  sum by (proxy_vendor) (increase(envoy_cluster_upstream_cx_rx_bytes_total[30d]))
) / 1e9 * 0.10
```

### Request-based Cost Calculation

```promql
# Cost per million requests (assuming $1.00/million)
sum by (proxy_vendor) (increase(envoy_cluster_upstream_rq_total[30d])) / 1e6 * 1.00
```

## Alerting Rules

```yaml
groups:
  - name: proxy_alerts
    rules:
      # High error rate
      - alert: ProxyHighErrorRate
        expr: proxy:error_rate:vendor > 0.10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate for {{ $labels.proxy_vendor }}"
          description: "Error rate is {{ $value | humanizePercentage }}"
      
      # Bandwidth spike
      - alert: ProxyBandwidthSpike
        expr: |
          (
            rate(envoy_cluster_upstream_cx_tx_bytes_total[5m]) +
            rate(envoy_cluster_upstream_cx_rx_bytes_total[5m])
          ) > 100e6  # 100 MB/s
        for: 10m
        labels:
          severity: info
        annotations:
          summary: "Bandwidth spike detected for {{ $labels.proxy_vendor }}"
      
      # Pod crashes
      - alert: CrawlerPodCrashing
        expr: rate(kube_pod_container_status_restarts_total{namespace="crawlers"}[1h]) > 0.1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Crawler pod {{ $labels.pod }} restarting frequently"
      
      # Metrics collection failing
      - alert: ProxyMetricsDown
        expr: up{job="crawler-envoy"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Proxy metrics collection down for {{ $labels.pod }}"
```

## Schema Validation

### Expected Metric Presence

All crawler pods should expose these metrics:

```bash
# Validation script
METRICS=(
  "envoy_cluster_upstream_rq_total"
  "envoy_cluster_upstream_cx_tx_bytes_total"
  "envoy_cluster_upstream_cx_rx_bytes_total"
  "envoy_cluster_upstream_rq_time_bucket"
)

for POD in $(kubectl get pods -n crawlers -l app=crawler -o name); do
  kubectl exec -n crawlers $POD -c envoy -- \
    wget -qO- localhost:15090/stats/prometheus | \
    grep -E "$(IFS=\|; echo "${METRICS[*]}")" > /dev/null
  
  if [ $? -eq 0 ]; then
    echo "[OK] $POD: Metrics OK"
  else
    echo "[ERROR] $POD: Metrics MISSING"
  fi
done
```

## Performance Benchmarks

### Expected Query Performance

| Query Type | Cardinality | Response Time | Notes |
|------------|-------------|---------------|-------|
| Vendor aggregate | Low (3-10) | < 100ms | Using recording rules |
| Per-pod metrics | Medium (100-1000) | < 500ms | Direct query |
| Destination analysis | High (10K+) | < 2s | With topk() limit |
| Historical trend (24h) | High | < 5s | Pre-aggregated data |

### Prometheus Resource Usage

| Metric | Development | Production |
|--------|-------------|------------|
| Active series | 10K-50K | 500K-2M |
| Sample ingestion rate | 5K/s | 50K-200K/s |
| Memory usage | 2GB | 8-16GB |
| Disk usage (30d) | 5GB | 50-100GB |

---

**Document Version**: 1.0  
**Last Updated**: 2025-10-07  
**Maintained By**: Platform Observability Team


