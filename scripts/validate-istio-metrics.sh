#!/usr/bin/env bash
#
# Validate Istio metrics are being collected
#

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Istio Metrics Validation                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check if Istio is installed
if ! kubectl get namespace istio-system &>/dev/null; then
    echo " Istio is not installed!"
    echo "Run: ./deploy-istio.sh"
    exit 1
fi

# Check if pods have Istio sidecars
echo "Step 1: Checking Istio sidecar injection..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SIDECAR_COUNT=$(kubectl get pods -n crawlers -o jsonpath='{range .items[*]}{.spec.containers[*].name}{"\n"}{end}' 2>/dev/null | grep -c "istio-proxy" 2>/dev/null || echo "0")

if [ "$SIDECAR_COUNT" -gt "0" ] 2>/dev/null; then
    echo "[OK] Found $SIDECAR_COUNT pods with Istio sidecars"
    echo ""
    echo "Pod details:"
    kubectl get pods -n crawlers -o custom-columns='NAME:.metadata.name,CONTAINERS:.spec.containers[*].name,READY:.status.containerStatuses[*].ready'
else
    echo " No Istio sidecars found!"
    echo ""
    echo "Check namespace label:"
    kubectl get namespace crawlers --show-labels
    echo ""
    echo "Pods should have 2 containers (load-generator + istio-proxy)"
    exit 1
fi
echo ""

# Port-forward Prometheus
echo "Step 2: Connecting to Prometheus..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl port-forward -n monitoring svc/prometheus 9090:9090 >/dev/null 2>&1 &
PF_PID=$!
sleep 5
echo "[OK] Connected"
echo ""

# Test Istio metrics
echo "Step 3: Querying Istio metrics..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Requirement A: Request count
echo "A. Request Count per Proxy Vendor:"
RESULT_A=$(curl -s 'http://localhost:9090/api/v1/query?query=sum%20by%20(proxy_vendor)%20(rate(istio_requests_total%5B5m%5D))' 2>/dev/null)
if echo "$RESULT_A" | grep -q "proxy_vendor"; then
    echo "[OK] SUCCESS - Metrics found!"
    echo "$RESULT_A" | grep -o '"proxy_vendor":"[^"]*"' | sort -u
else
    echo "  No data yet (this is normal within first 2-3 minutes)"
fi
echo ""

# Requirement B: Destination tracking
echo "B. Destination Tracking:"
RESULT_B=$(curl -s 'http://localhost:9090/api/v1/query?query=topk(5,%20sum%20by%20(destination_service_name,%20proxy_vendor)%20(rate(istio_requests_total%5B5m%5D)))' 2>/dev/null)
if echo "$RESULT_B" | grep -q "destination"; then
    echo "[OK] SUCCESS - Destination metrics found!"
else
    echo "  No destination data yet"
fi
echo ""

# Requirement C: Bandwidth sent
echo "C. Bandwidth Sent (Outgoing):"
RESULT_C=$(curl -s 'http://localhost:9090/api/v1/query?query=sum%20by%20(proxy_vendor)%20(rate(istio_request_bytes_sum%5B5m%5D))' 2>/dev/null)
if echo "$RESULT_C" | grep -q "proxy_vendor"; then
    echo "[OK] SUCCESS - Outgoing bandwidth metrics found!"
else
    echo "  No bandwidth data yet"
fi
echo ""

# Requirement D: Bandwidth received
echo "D. Bandwidth Received (Incoming):"
RESULT_D=$(curl -s 'http://localhost:9090/api/v1/query?query=sum%20by%20(proxy_vendor)%20(rate(istio_response_bytes_sum%5B5m%5D))' 2>/dev/null)
if echo "$RESULT_D" | grep -q "proxy_vendor"; then
    echo "[OK] SUCCESS - Incoming bandwidth metrics found!"
else
    echo "[WARN] No bandwidth data yet"
fi
echo ""

# Cleanup
kill $PF_PID 2>/dev/null

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if echo "$RESULT_A$RESULT_B$RESULT_C$RESULT_D" | grep -q "proxy_vendor"; then
    echo " Istio metrics are flowing correctly!"
    echo ""
    echo "Open Grafana to view dashboards:"
    echo "  kubectl port-forward -n monitoring svc/grafana 3000:80"
    echo "  http://localhost:3000 (admin/admin)"
else
    echo "  No metrics yet - this is normal within first 2-3 minutes after deployment"
    echo ""
    echo "Wait 2-3 minutes and run this script again"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check if pods are running:"
    echo "     kubectl get pods -n crawlers"
    echo "  2. Check load generator logs:"
    echo "     kubectl logs -n crawlers -l app=load-generator -c load-generator --tail=20"
    echo "  3. Check Istio sidecar logs:"
    echo "     kubectl logs -n crawlers -l app=load-generator -c istio-proxy --tail=20"
fi

echo ""


