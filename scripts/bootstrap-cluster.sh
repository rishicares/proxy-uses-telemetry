#!/usr/bin/env bash
#
# Bootstrap Kubernetes cluster for proxy telemetry testing
# Supports both minikube and k3s
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_TYPE="${CLUSTER_TYPE:-minikube}"  # minikube or k3s
MINIKUBE_CPUS="${MINIKUBE_CPUS:-4}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-8192}"
MINIKUBE_DISK="${MINIKUBE_DISK:-20g}"
K8S_VERSION="${K8S_VERSION:-v1.28.0}"

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi
    
    if [[ "$CLUSTER_TYPE" == "minikube" ]] && ! command -v minikube &> /dev/null; then
        missing_tools+=("minikube")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and try again."
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

start_minikube() {
    log_info "Starting Minikube cluster..."
    
    if minikube status &> /dev/null; then
        log_warning "Minikube cluster already running"
        read -p "Do you want to delete and recreate it? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            minikube delete
        else
            log_info "Using existing cluster"
            return 0
        fi
    fi
    
    minikube start \
        --cpus="$MINIKUBE_CPUS" \
        --memory="$MINIKUBE_MEMORY" \
        --disk-size="$MINIKUBE_DISK" \
        --kubernetes-version="$K8S_VERSION" \
        --driver=docker
    
    log_success "Minikube cluster started"
    
    # Enable addons
    log_info "Enabling Minikube addons..."
    minikube addons enable metrics-server
    log_success "Addons enabled"
}

start_k3s() {
    log_info "Installing k3s cluster..."
    
    if systemctl is-active --quiet k3s; then
        log_warning "k3s is already running"
        return 0
    fi
    
    curl -sfL https://get.k3s.io | sh -
    
    # Wait for k3s to be ready
    sleep 10
    
    # Configure kubectl
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    
    log_success "k3s cluster started"
}

verify_cluster() {
    log_info "Verifying cluster..."
    
    kubectl cluster-info
    kubectl get nodes
    
    # Wait for nodes to be ready
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    
    log_success "Cluster is ready"
}

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     Proxy Telemetry - Cluster Bootstrap                   ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_prerequisites
    
    if [[ "$CLUSTER_TYPE" == "minikube" ]]; then
        start_minikube
    elif [[ "$CLUSTER_TYPE" == "k3s" ]]; then
        start_k3s
    else
        log_error "Unknown cluster type: $CLUSTER_TYPE"
        log_info "Supported types: minikube, k3s"
        exit 1
    fi
    
    verify_cluster
    
    echo ""
    log_success "Cluster bootstrap completed!"
    echo ""
    log_info "Next steps:"
    echo "  1. Deploy the monitoring stack: ./scripts/deploy-all.sh"
    echo "  2. Access dashboards: ./scripts/open-dashboards.sh"
    echo "  3. Validate metrics: ./scripts/validate-metrics.sh"
    echo ""
}

main "$@"


