#!/usr/bin/env bash
#
# Simplified All-in-One Deployment Script
# Helm hooks automatically install: Istio -> Prometheus -> Grafana -> Load Generators
#
# Usage:
#   ./deploy.sh                    # Interactive mode (prompts for dashboard opening)
#   AUTO_OPEN=y ./deploy.sh        # Auto-open dashboards without prompting
#   AUTO_OPEN=n ./deploy.sh        # Skip dashboard opening without prompting
#

set -euo pipefail

# Colors for output
RED='\033[0,31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_wait() {
    echo -e "${YELLOW}⏳${NC} $1"
}

echo ""
echo "========================================================================="
echo "  Proxy Telemetry - Complete Self-Contained Package"
echo "  (Istio + Prometheus + Grafana + Load Generators)"
echo "========================================================================="
echo ""

# Step 1: Clean up existing deployment
log_info "Step 1/3: Cleaning up existing resources..."
helm uninstall proxy-telemetry -n monitoring 2>/dev/null || true

# Check if namespaces exist without Helm labels (orphaned namespaces)
for ns in monitoring crawlers; do
    if kubectl get namespace "$ns" &>/dev/null; then
        # Check if namespace has Helm management labels
        HELM_MANAGED=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || echo "")
        if [[ -z "$HELM_MANAGED" ]]; then
            log_info "  Removing orphaned namespace: $ns"
            kubectl delete namespace "$ns" --wait=true --timeout=90s 2>/dev/null || true
        fi
    fi
done

log_wait "Waiting for cleanup to complete..."
sleep 10
log_success "Cleanup complete"
echo ""

# Step 2: Create required namespaces (only if they don't exist)
log_info "Step 2/3: Preparing namespaces..."
# Note: We don't create namespaces manually here to avoid conflicts
# Helm will create them with proper labels via templates
log_success "Ready for Helm deployment"
echo ""

# Step 3: Deploy complete stack via Helm
log_info "Step 3/3: Deploying complete stack with Helm..."
echo ""
log_info "  What Helm will do automatically:"
log_info "     1. Pre-install hook: Check/Install Istio"
log_info "     2. Deploy Prometheus with Istio scraping"
log_info "     3. Deploy Grafana with 4 dashboards"
log_info "     4. Deploy Load Generators with Istio sidecars"
log_info "     5. Post-install hook: Validate stack health"
echo ""
log_wait "Starting deployment (this may take 3-5 minutes)..."
echo ""

# Attempt deployment
DEPLOY_OUTPUT=$(mktemp)
if helm install proxy-telemetry ./helm/proxy-telemetry \
    --namespace monitoring \
    --create-namespace \
    --wait \
    --timeout 15m 2>&1 | tee "$DEPLOY_OUTPUT"; then
    rm -f "$DEPLOY_OUTPUT"
else
    DEPLOY_EXIT_CODE=$?
    
    # Check if it's the namespace ownership error
    if grep -q "invalid ownership metadata" "$DEPLOY_OUTPUT" || grep -q "missing key.*managed-by" "$DEPLOY_OUTPUT"; then
        log_error "Detected orphaned namespaces. Attempting automatic fix..."
        rm -f "$DEPLOY_OUTPUT"
        
        # Force delete namespaces
        for ns in monitoring crawlers; do
            if kubectl get namespace "$ns" &>/dev/null; then
                log_info "  Force-deleting namespace: $ns"
                kubectl delete namespace "$ns" --force --grace-period=0 2>/dev/null || true
            fi
        done
        
        log_wait "Waiting for namespace deletion (30 seconds)..."
        sleep 30
        
        # Retry deployment
        log_info "Retrying deployment..."
        echo ""
        if helm install proxy-telemetry ./helm/proxy-telemetry \
            --namespace monitoring \
            --create-namespace \
            --wait \
            --timeout 15m; then
            log_success "Deployment succeeded after fixing namespace ownership!"
        else
            log_error "Deployment failed even after fixing namespaces!"
            echo ""
            echo "Troubleshooting:"
            echo "  kubectl logs -n monitoring -l app=istio-installer"
            echo "  kubectl get pods -n monitoring"
            echo "  kubectl get pods -n crawlers"
            exit 1
        fi
    else
        # Different error, show original troubleshooting
        rm -f "$DEPLOY_OUTPUT"
        log_error "Deployment failed!"
        echo ""
        echo "Troubleshooting:"
        echo "  kubectl logs -n monitoring -l app=istio-installer"
        echo "  kubectl get pods -n monitoring"
        echo "  kubectl get pods -n crawlers"
        exit $DEPLOY_EXIT_CODE
    fi
fi

echo ""
log_success "Complete stack deployed successfully!"
echo ""

# Display deployment status
echo "Deployment Status:"
echo ""
echo "Monitoring Namespace:"
kubectl get pods -n monitoring -o wide 2>/dev/null || echo "  No pods yet"
echo ""
echo "Crawlers Namespace:"
kubectl get pods -n crawlers -o wide 2>/dev/null || echo "  No pods yet"
echo ""

# Wait a bit for pods to stabilize
log_wait "Waiting for pods to stabilize (30 seconds)..."
sleep 30

echo ""
echo "========================================================================="
echo "                     DEPLOYMENT COMPLETE"
echo "========================================================================="
echo ""
echo "All components are now running:"
echo "  - Istio service mesh"
echo "  - Prometheus"
echo "  - Grafana with 4 dashboards"
echo "  - Load Generators (9 pods with Istio sidecars)"
echo ""

# Run validation automatically
log_info "Running metrics validation..."
echo ""
if ./scripts/validate-istio-metrics.sh; then
    echo ""
    log_success "All metrics validated successfully!"
else
    echo ""
    log_error "Metrics validation failed. May need more time for metrics to accumulate."
    log_info "You can re-run validation with: ./scripts/validate-istio-metrics.sh"
fi

echo ""
echo "========================================================================="
echo "                     ACCESS DASHBOARDS"
echo "========================================================================="
echo ""

# Offer to open dashboards automatically (or use AUTO_OPEN env var)
if [[ -n "${AUTO_OPEN:-}" ]]; then
    REPLY="$AUTO_OPEN"
    log_info "AUTO_OPEN=$AUTO_OPEN detected (non-interactive mode)"
else
    read -p "Would you like to open dashboards now? (y/n) [y]: " -n 1 -r
    echo ""
    REPLY=${REPLY:-y}
fi

if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Starting port forwards and opening dashboards..."
    echo ""
    
    # Clean up any existing port forwards
    pkill -f "port-forward.*grafana" 2>/dev/null || true
    pkill -f "port-forward.*prometheus" 2>/dev/null || true
    sleep 2
    
    # Start port forwards in background
    kubectl port-forward -n monitoring svc/grafana 3000:80 > /dev/null 2>&1 &
    GRAFANA_PID=$!
    
    kubectl port-forward -n monitoring svc/prometheus 9090:9090 > /dev/null 2>&1 &
    PROMETHEUS_PID=$!
    
    sleep 3
    
    log_success "Port forwards started:"
    echo "  - Grafana PID: $GRAFANA_PID"
    echo "  - Prometheus PID: $PROMETHEUS_PID"
    echo ""
    
    # Open browsers (cross-platform)
    if command -v xdg-open > /dev/null 2>&1; then
        log_info "Opening Grafana in browser..."
        xdg-open http://localhost:3000 2>/dev/null &
    elif command -v open > /dev/null 2>&1; then
        log_info "Opening Grafana in browser..."
        open http://localhost:3000 2>/dev/null &
    else
        log_info "Could not detect browser opener. Please open manually:"
    fi
    
    echo ""
    echo "Dashboard URLs:"
    echo "   Grafana:    http://localhost:3000"
    echo "      Username:   admin"
    echo "      Password:   admin"
    echo ""
    echo "   Prometheus: http://localhost:9090"
    echo ""
    echo "Port forwards are running in the background."
    echo "To stop them later, run:"
    echo "  pkill -f 'port-forward.*grafana'"
    echo "  pkill -f 'port-forward.*prometheus'"
    echo ""
else
    echo ""
    echo "To access dashboards manually:"
    echo ""
    echo "  Grafana (4 dashboards with live data):"
    echo "    kubectl port-forward -n monitoring svc/grafana 3000:80"
    echo "    URL: http://localhost:3000"
    echo "    Username: admin | Password: admin"
    echo ""
    echo "  Prometheus (metrics & queries):"
    echo "    kubectl port-forward -n monitoring svc/prometheus 9090:9090"
    echo "    URL: http://localhost:9090"
    echo ""
    echo "  Or run: ./scripts/open-dashboards.sh"
    echo ""
fi

echo "========================================================================="
echo ""
echo "Quick Commands:"
echo "  View pods:        kubectl get pods -n crawlers -n monitoring"
echo "  View logs:        kubectl logs -n crawlers -l app=load-generator --tail=50"
echo "  Scale traffic:    kubectl scale deployment -n crawlers --all --replicas=5"
echo "  Re-validate:      ./scripts/validate-istio-metrics.sh"
echo ""
echo "========================================================================="
echo ""
