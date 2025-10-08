#!/usr/bin/env bash
#
# Open Grafana and Prometheus dashboards
#

set -e

# Colors for output
RED='\033[0;31m'
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

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

cleanup() {
    log_info "Stopping port forwards..."
    pkill -f "port-forward.*grafana" || true
    pkill -f "port-forward.*prometheus" || true
}

trap cleanup EXIT

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     Proxy Telemetry - Dashboard Access                    ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    log_info "Setting up port forwards..."
    
    # Port forward Grafana
    kubectl port-forward -n monitoring svc/grafana 3000:80 > /dev/null 2>&1 &
    GRAFANA_PID=$!
    
    # Port forward Prometheus
    kubectl port-forward -n monitoring svc/prometheus 9090:9090 > /dev/null 2>&1 &
    PROMETHEUS_PID=$!
    
    # Wait for port forwards
    sleep 3
    
    log_success "Port forwards established"
    
    # Get Grafana password
    GRAFANA_PASSWORD=$(kubectl get secret -n monitoring grafana-admin -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "admin")
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  Grafana Dashboard"
    echo "═══════════════════════════════════════════════════════════"
    echo "  URL:      http://localhost:3000"
    echo "  Username: admin"
    echo "  Password: $GRAFANA_PASSWORD"
    echo ""
    echo "  Dashboards:"
    echo "    • Proxy Overview"
    echo "    • Bandwidth Analytics"
    echo "    • Performance & Health"
    echo "    • Destination Tracking"
    echo ""
    
    echo "═══════════════════════════════════════════════════════════"
    echo "  Prometheus"
    echo "═══════════════════════════════════════════════════════════"
    echo "  URL: http://localhost:9090"
    echo ""
    
    # Try to open in browser
    if command -v xdg-open &> /dev/null; then
        xdg-open "http://localhost:3000" 2>/dev/null || true
    elif command -v open &> /dev/null; then
        open "http://localhost:3000" 2>/dev/null || true
    fi
    
    log_info "Press Ctrl+C to stop port forwards and exit"
    
    # Keep running
    wait
}

main "$@"


