# Architecture Document

## Executive Summary

This document describes the architecture of a production-ready Kubernetes proxy usage telemetry system that monitors outbound proxy traffic from thousands of crawler pods, providing accurate metrics attribution to third-party proxy vendors.

## Problem Statement

### Requirements

A large Kubernetes cluster runs thousands of crawler pods that use multiple third-party proxy vendors. The system must:

1. **Track requests** sent via each proxy vendor (count)
2. **Monitor destinations** (domain/host and/or remote IP)
3. **Measure outbound bandwidth** per proxy per pod (bytes sent)
4. **Measure inbound bandwidth** per proxy per pod (bytes received)

### Constraints

- Support **HTTP and HTTPS** protocols
- Support **HTTP/1.1 and HTTP/2**
- Work with **millions of proxy IPs** across multiple vendors
- Scale to **thousands of crawler pods**
- Use only **open-source technologies**

### Challenges

1. **Vendor Attribution**: How to map millions of proxy IPs to vendors
2. **HTTPS Visibility**: Encrypted traffic hides destination information
3. **Scale**: Collecting metrics from thousands of pods without overwhelming monitoring infrastructure
4. **Zero-Touch**: Minimize changes to crawler application code

## Solution Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Crawler Namespace                           │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Crawler Pod (label: proxy-vendor=vendor-a)                  │  │
│  │                                                               │  │
│  │  ┌──────────────┐                 ┌───────────────────────┐ │  │
│  │  │              │  HTTP_PROXY=    │                       │ │  │
│  │  │  Crawler     │  localhost:8888 │   Envoy Sidecar      │ │──┼─▶ External
│  │  │  Application │ ───────────────▶│   - Proxy on :8888   │ │  │   Destinations
│  │  │              │                 │   - Metrics on :15090 │ │  │
│  │  └──────────────┘                 └───────────────────────┘ │  │
│  │                                              │                │  │
│  └──────────────────────────────────────────────┼────────────────┘  │
│                                                 │                   │
│  ┌──────────────────────────────────────────────┼────────────────┐  │
│  │  Crawler Pod (label: proxy-vendor=vendor-b)  │                │  │
│  │  [Similar structure]                         │                │  │
│  └──────────────────────────────────────────────┼────────────────┘  │
│                                                 │                   │
└─────────────────────────────────────────────────┼───────────────────┘
                                                  │
                                   ┌──────────────▼──────────────┐
                                   │   Prometheus (scrapes       │
                                   │   :15090 every 15s)         │
                                   │   - 30 day retention        │
                                   │   - Recording rules         │
                                   │   - Alerting rules          │
                                   └──────────────┬──────────────┘
                                                  │
                                   ┌──────────────▼──────────────┐
                                   │   Grafana                   │
                                   │   - 4 Pre-built dashboards  │
                                   │   - Real-time visualization │
                                   └─────────────────────────────┘
```

### Core Components

#### 1. Envoy Proxy Sidecar

**Purpose**: Intercept and meter all outbound HTTP/HTTPS traffic

**Configuration**:
```yaml
listeners:
  - name: http_proxy_listener
    address: 0.0.0.0:8888
    filters:
      - http_connection_manager
        - dynamic_forward_proxy  # Handles both HTTP and HTTPS CONNECT
```

**Key Features**:
- **Dynamic forward proxy**: Routes to any destination without predefined clusters
- **CONNECT tunneling**: Supports HTTPS proxying transparently
- **Metrics export**: Exposes Prometheus metrics on port 15090
- **Access logging**: Detailed request/response logging

**Resource Requirements**:
- Memory: 128 MB (request), 256 MB (limit)
- CPU: 100m (request), 500m (limit)
- ~50 MB actual usage per pod

#### 2. Vendor Attribution System

**Strategy**: Pod labels + Prometheus relabeling

**Implementation**:

1. **Pod Labeling**:
   ```yaml
   metadata:
     labels:
       proxy-vendor: vendor-a
   ```

2. **Kubernetes Service Discovery**:
   ```yaml
   kubernetes_sd_configs:
     - role: pod
       namespaces:
         names: [crawlers]
   ```

3. **Prometheus Relabeling**:
   ```yaml
   relabel_configs:
     - source_labels: [__meta_kubernetes_pod_label_proxy_vendor]
       action: replace
       target_label: proxy_vendor
   ```

4. **Envoy Tag Injection**:
   ```yaml
   stats_tags:
     - tag_name: proxy_vendor
       fixed_value: "vendor-a"  # Injected via init container
   ```

**Advantages**:
- [+] No IP range mapping needed
- [+] Works with millions of IPs
- [+] Simple and deterministic
- [+] No external database required

**Trade-offs**:
- [!] Requires pod label management
- [!] Crawler deployment must specify vendor

#### 3. Metrics Collection Pipeline

**Data Flow**:

```
Envoy Sidecar → Prometheus → Recording Rules → Grafana
    (15s)          (scrape)      (aggregate)    (visualize)
```

**Prometheus Configuration**:
- **Scrape interval**: 15 seconds
- **Retention**: 30 days (configurable)
- **Storage**: 100 GB persistent volume
- **Recording rules**: 15-second evaluation interval

**Key Metrics Exported**:

| Metric | Type | Description |
|--------|------|-------------|
| `envoy_cluster_upstream_rq_total` | Counter | Total requests |
| `envoy_cluster_upstream_cx_tx_bytes_total` | Counter | Bytes sent |
| `envoy_cluster_upstream_cx_rx_bytes_total` | Counter | Bytes received |
| `envoy_cluster_upstream_rq_time` | Histogram | Request latency |

**Labels**:
- `proxy_vendor`: Vendor identifier
- `pod_name`: Pod instance
- `destination_host`: Target hostname (HTTP only)
- `response_code`: HTTP status code
- `response_code_class`: 2xx, 4xx, 5xx

#### 4. Recording Rules for Performance

Pre-aggregate high-cardinality metrics:

```yaml
- record: proxy:requests_per_second:vendor
  expr: sum by (proxy_vendor) (rate(envoy_cluster_upstream_rq_total[5m]))

- record: proxy:bandwidth_per_pod:vendor_pod
  expr: sum by (proxy_vendor, pod_name) (
    rate(envoy_cluster_upstream_cx_tx_bytes_total[5m]) +
    rate(envoy_cluster_upstream_cx_rx_bytes_total[5m])
  )
```

**Benefits**:
- Fast sub-second dashboard query response
- Reduces query load on Prometheus
- Simplifies dashboard queries

### Protocol Support

#### HTTP/1.1

**Mechanism**: Standard HTTP proxy

```
Crawler → Envoy → Destination
GET http://example.com/path HTTP/1.1
Host: example.com
```

**Visibility**:
- [+] Full request headers
- [+] Destination host
- [+] Request/response bodies (if needed)

#### HTTPS via CONNECT Tunnel

**Mechanism**: HTTP CONNECT method

```
Crawler → Envoy → Destination
CONNECT example.com:443 HTTP/1.1

[Encrypted TLS tunnel]
```

**Visibility**:
- [+] Destination IP and port (from CONNECT)
- [+] SNI hostname (from TLS handshake)
- [-] Request headers (encrypted)
- [-] Response body (encrypted)

#### HTTP/2

**Mechanism**: Automatic protocol detection

- Envoy auto-detects HTTP/2
- Works for both cleartext (h2c) and TLS (h2)
- Multiplexed streams tracked individually

### Scalability Architecture

#### Metrics Cardinality Management

**Challenge**: High-cardinality labels can explode time series count

**Cardinality Estimates**:

| Label | Cardinality | Impact |
|-------|-------------|--------|
| `proxy_vendor` | 3-10 | Low [+] |
| `pod_name` | 100-5000 | Medium [!] |
| `destination_host` | 1K-100K | High [!] |
| `destination_ip` | 5K-1M | Very High [!!] |

**Mitigation Strategies**:

1. **Recording rules** drop high-cardinality labels
2. **Metric relabeling** limits destination tracking
3. **Retention policies** balance detail vs. cost
4. **Sampling** for very large scale (optional)

#### Resource Scaling

**Small Scale (100-500 pods)**:
```yaml
prometheus:
  resources:
    memory: 2Gi
    cpu: 1
```

**Medium Scale (500-2000 pods)**:
```yaml
prometheus:
  resources:
    memory: 8Gi
    cpu: 2
  retention:
    time: 15d  # Reduce retention
```

**Large Scale (2000+ pods)**:
- Prometheus federation (multiple instances)
- Thanos/Cortex for long-term storage
- Increased scrape intervals (30s-60s)

### Deployment Model

#### Helm Chart Structure

```
helm/proxy-telemetry/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── namespaces.yaml
│   ├── prometheus-deployment.yaml
│   ├── prometheus-configmap.yaml
│   ├── grafana-deployment.yaml
│   ├── grafana-dashboards.yaml
│   ├── envoy-configmap.yaml
│   ├── load-generator.yaml
│   └── NOTES.txt
```

#### Namespace Isolation

- **monitoring**: Prometheus, Grafana (stable infrastructure)
- **crawlers**: Load generators, crawler pods (dynamic workloads)

**Benefits**:
- Resource quota management
- RBAC isolation
- Network policy enforcement

### Security Architecture

#### Pod Security

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 65534
  fsGroup: 65534
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop: [ALL]
```

#### Network Security

- Network policies restrict ingress/egress
- No privileged containers
- ReadOnlyRootFilesystem where possible

#### Secrets Management

- Grafana password stored in Kubernetes Secret
- No hardcoded credentials in images
- RBAC limits secret access

### Observability of Observability

**Monitoring the Monitor**:

```yaml
# Self-monitoring
- job_name: 'prometheus'
  static_configs:
    - targets: ['localhost:9090']

# Alerting on collection failures
- alert: ProxyMetricsDown
  expr: up{job="crawler-envoy"} == 0
  for: 2m
```

**Health Checks**:
- Prometheus liveness/readiness probes
- Grafana datasource health checks
- Envoy admin interface monitoring

## Trade-offs and Decisions

### 1. Sidecar vs. Daemonset vs. Service Mesh

**Decision**: Sidecar (Envoy per pod)

**Alternatives Considered**:

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **Sidecar** | Per-pod isolation, no single point of failure | Resource overhead | [CHOSEN] |
| **DaemonSet** | Lower resource usage | Attribution complexity | [REJECTED] |
| **Istio** | Feature-rich | Overkill, designed for east-west | [REJECTED] |

**Rationale**: Per-pod sidecars provide the best isolation and attribution with acceptable resource overhead.

### 2. Pod Labels vs. IP Range Mapping

**Decision**: Pod labels for vendor attribution

**Alternatives Considered**:

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **Pod Labels** | Simple, deterministic | Requires label management | [CHOSEN] |
| **IP Ranges** | Automatic | Requires vendor IP database | [COMPLEX] |
| **DNS Tracking** | Works for named proxies | Doesn't work for IP-based | [LIMITED] |
| **HTTP Headers** | Explicit | Requires app changes, HTTPS issue | [INTRUSIVE] |

**Rationale**: Pod labels are the simplest and most reliable method that works for all proxy types.

### 3. Envoy vs. Nginx vs. Haproxy

**Decision**: Envoy Proxy

**Comparison**:

| Feature | Envoy | Nginx | HAProxy |
|---------|-------|-------|---------|
| Dynamic forward proxy | [YES] | [NO] | [NO] |
| Prometheus metrics | [NATIVE] | [PLUGIN] | [PLUGIN] |
| HTTP/2 support | [FULL] | [FULL] | [FULL] |
| CONNECT tunneling | [BUILT-IN] | [MODULE] | [BUILT-IN] |
| Configuration reload | [HOT] | [RELOAD] | [HOT] |

**Rationale**: Envoy's dynamic forward proxy and native Prometheus integration make it ideal for this use case.

### 4. Prometheus vs. InfluxDB vs. Elasticsearch

**Decision**: Prometheus

**Rationale**:
- Industry standard for metrics
- Excellent Kubernetes integration
- Powerful query language (PromQL)
- Native Grafana support
- Lower resource requirements than Elasticsearch

## Failure Modes and Mitigations

### 1. Envoy Sidecar Crash

**Impact**: Crawler pod cannot make outbound requests

**Mitigation**:
- Liveness probes with automatic restart
- PodDisruptionBudget ensures availability
- Resource limits prevent OOM

### 2. Prometheus Overload

**Impact**: Metrics collection fails or lags

**Mitigation**:
- Recording rules reduce query load
- Horizontal scaling via federation
- Retention policies limit storage growth
- Alerting on collection failures

### 3. High Cardinality Explosion

**Impact**: Prometheus memory exhaustion

**Mitigation**:
- Metric relabeling drops high-cardinality labels
- Recording rules pre-aggregate
- Monitoring of time series count
- Automatic cleanup of stale metrics

### 4. Network Partition

**Impact**: Cannot scrape metrics from crawler pods

**Mitigation**:
- Prometheus scrape failures trigger alerts
- Metrics buffered in Envoy (limited)
- Multi-region deployment (production)

## Performance Characteristics

### Latency Impact

**Request Overhead**:
- Envoy proxy: ~1-5ms added latency
- Acceptable for crawler use case
- Can be reduced with tuning

**Metrics Collection**:
- Prometheus scrape: < 100ms per pod
- Recording rule evaluation: < 1s
- Dashboard query: < 2s (with recording rules)

### Resource Usage

**Per Crawler Pod**:
- Envoy sidecar: ~50 MB RAM, 0.1 CPU
- Marginal network overhead (metrics export)

**Monitoring Stack**:
- Prometheus: 2-16 GB RAM (scale-dependent)
- Grafana: 512 MB RAM
- Total: ~3-17 GB for monitoring infrastructure

**Storage**:
- ~1 GB/day for 1000 pods (uncompressed)
- 10:1 compression ratio in TSDB
- ~3 GB/month with 30-day retention

## Production Readiness

### Checklist

[+] High Availability: PodDisruptionBudget configured  
[+] Auto-scaling: HPA for load generators  
[+] Monitoring: Self-monitoring with alerts  
[+] Security: Non-root, seccomp, network policies  
[+] Documentation: Comprehensive guides  
[+] Testing: Validation scripts included  
[+] Rollback: Helm-based deployment  
[+] Logging: Structured logs with labels  

### SLOs

**Metrics Collection**:
- Availability: 99.9%
- Scrape success rate: > 99%
- Query latency (p95): < 2s

**Crawler Impact**:
- Request latency overhead: < 10ms p95
- Sidecar CPU usage: < 5% of crawler CPU
- Sidecar memory: < 100 MB per pod

## Future Enhancements

### Short Term
1. GeoIP tracking for destination geography
2. Custom metrics for application-specific tracking
3. Alertmanager integration for PagerDuty/Slack
4. Cost attribution dashboards

### Long Term
1. Thanos for long-term storage (years)
2. Machine learning for anomaly detection
3. Auto-scaling based on proxy performance
4. Multi-cluster federation

---

**Document Version**: 1.0  
**Last Updated**: 2025-10-07  
**Author**: Platform Observability Team  
**Review Status**: Approved for Implementation


