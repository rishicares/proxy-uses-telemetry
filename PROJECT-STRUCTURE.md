# Project Structure

Production-ready file organization for the Kubernetes Proxy Usage Telemetry solution.

```
.
├── README.md                           # Main documentation & quick start
├── ARCHITECTURE.md                     # Architecture deep-dive & design decisions
├── DATA-MODEL.md                       # Metrics schema & PromQL queries
├── DEMO-GUIDE.md                       # Live demonstration script
├── DEPLOYMENT.md                       # Comprehensive deployment guide
├── PROJECT-STRUCTURE.md                # This file
│
├── deploy.sh                           # Main deployment script
├── Makefile                            # Convenience commands
│
├── helm/                               # Helm chart
│   └── proxy-telemetry/
│       ├── Chart.yaml                  # Chart metadata
│       ├── values.yaml                 # Configuration values
│       ├── istio-telemetry.yaml        # Istio telemetry config (header extraction)
│       └── templates/                  # Kubernetes manifests
│           ├── _helpers.tpl
│           ├── NOTES.txt               # Post-install instructions
│           ├── grafana-dashboards.yaml # Dashboard definitions
│           ├── grafana-deployment.yaml # Grafana deployment
│           ├── load-generator.yaml     # Crawler simulator
│           ├── prometheus-configmap.yaml # Prometheus config (w/ Istio scrape)
│           └── prometheus-deployment.yaml # Prometheus deployment
│
└── scripts/                            # Utility scripts
    ├── bootstrap-cluster.sh            # Start minikube cluster
    ├── open-dashboards.sh              # Port-forward Grafana
    └── validate-istio-metrics.sh       # Validate all 4 requirements
```

## Key Files

### Documentation

| File | Purpose | Audience |
|------|---------|----------|
| `README.md` | Main entry point, quick start, overview | Everyone |
| `DEPLOYMENT.md` | Detailed deployment guide, troubleshooting | Operators |
| `ARCHITECTURE.md` | Design decisions, trade-offs | Engineers |
| `DATA-MODEL.md` | Metrics schema, PromQL queries | Developers |
| `DEMO-GUIDE.md` | Live demonstration script | Presenters |
| `PROJECT-STRUCTURE.md` | File organization (this file) | Contributors |

### Deployment

| File | Purpose |
|------|---------|
| `deploy.sh` | **Main deployment script** - Run this to deploy everything |
| `Makefile` | Convenience targets (`make deploy`, `make validate`, etc.) |

### Configuration

| File | Purpose |
|------|---------|
| `helm/proxy-telemetry/values.yaml` | Main configuration (vendors, resources, traffic) |
| `helm/proxy-telemetry/istio-telemetry.yaml` | Istio telemetry API (header extraction) |

### Scripts

| File | Purpose |
|------|---------|
| `scripts/bootstrap-cluster.sh` | Start fresh minikube cluster |
| `scripts/validate-istio-metrics.sh` | **Validate all 4 requirements** |
| `scripts/open-dashboards.sh` | Port-forward Grafana |

## Deleted Files (Cleanup)

The following files were removed to achieve production standards:

### Duplicate Documentation
- ~~`DASHBOARD-TROUBLESHOOTING.md`~~ → Integrated into DEPLOYMENT.md
- ~~`DEPLOY-NOW.md`~~ → Combined into README.md
- ~~`DEPLOYMENT-GUIDE.md`~~ → Replaced with DEPLOYMENT.md
- ~~`GRAFANA-DASHBOARDS-GUIDE.md`~~ → Integrated into docs
- ~~`INSTRUCTIONS.txt`~~ → Combined into README.md
- ~~`ISTIO-MIGRATION.md`~~ → Migration history not needed
- ~~`ISTIO-START-HERE.md`~~ → Combined into README.md
- ~~`RUN-ME.txt`~~ → Combined into README.md
- ~~`SOLUTION-OVERVIEW.md`~~ → Integrated into README.md
- ~~`START-HERE.md`~~ → Combined into README.md

### Old/Broken Scripts
- ~~`FIX-NO-DATA.sh`~~ → Workaround no longer needed
- ~~`scripts/deploy-all.sh`~~ → Replaced with deploy.sh
- ~~`scripts/diagnose.sh`~~ → For broken Envoy approach
- ~~`scripts/import-dashboards.sh`~~ → Workaround not needed
- ~~`scripts/install-istio.sh`~~ → Integrated into deploy.sh
- ~~`scripts/validate-metrics.sh`~~ → Replaced with validate-istio-metrics.sh

### Unnecessary Helm Templates
- ~~`helm/proxy-telemetry/templates/envoy-configmap.yaml`~~ → Istio manages config
- ~~`helm/proxy-telemetry/templates/namespaces.yaml`~~ → Created by deploy script
- ~~`helm/proxy-telemetry/templates/prometheus-istio-scrape.yaml`~~ → Consolidated into prometheus-configmap.yaml

## Quick Reference

### Deploy
```bash
./deploy.sh
```

### Validate
```bash
./scripts/validate-istio-metrics.sh
```

### Access
```bash
# Grafana (admin/admin)
kubectl port-forward -n monitoring svc/grafana 3000:80

# Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

### Make Commands
```bash
make help          # Show all available commands
make bootstrap     # Start minikube cluster
make deploy        # Deploy everything
make validate      # Validate metrics
make dashboards    # Port-forward Grafana
make status        # Show deployment status
make clean         # Remove deployment
```


