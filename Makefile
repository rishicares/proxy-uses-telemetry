.PHONY: help bootstrap deploy validate dashboards clean lint test all

# Default target
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

help: ## Show this help message
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║          Proxy Telemetry - Build Commands                 ║"
	@echo "╚════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""

bootstrap: ## Bootstrap Kubernetes cluster (minikube)
	@echo "$(GREEN)Bootstrapping cluster...$(NC)"
	./scripts/bootstrap-cluster.sh

deploy: ## Deploy the complete stack (Istio-based)
	@echo "$(GREEN)Deploying stack...$(NC)"
	./deploy.sh

validate: ## Validate metrics collection
	@echo "$(GREEN)Validating metrics...$(NC)"
	./scripts/validate-istio-metrics.sh

dashboards: ## Open Grafana and Prometheus dashboards
	@echo "$(GREEN)Opening dashboards...$(NC)"
	./scripts/open-dashboards.sh

lint: ## Lint Helm chart
	@echo "$(GREEN)Linting Helm chart...$(NC)"
	helm lint ./helm/proxy-telemetry

test: lint validate ## Run all tests

clean: ## Clean up all resources
	@echo "$(YELLOW)Cleaning up resources...$(NC)"
	helm uninstall proxy-telemetry -n monitoring || true
	kubectl delete namespace monitoring crawlers || true
	istioctl uninstall --purge -y 2>/dev/null || true
	@echo "$(GREEN)Cleanup complete$(NC)"

clean-cluster: ## Delete the entire cluster
	@echo "$(YELLOW)Deleting cluster...$(NC)"
	@read -p "Are you sure you want to delete the cluster? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		minikube delete; \
		echo "$(GREEN)Cluster deleted$(NC)"; \
	else \
		echo "$(YELLOW)Cancelled$(NC)"; \
	fi

scale-up: ## Scale load generators to 10 replicas each
	@echo "$(GREEN)Scaling up load generators...$(NC)"
	kubectl scale deployment -n crawlers load-generator-vendor-a --replicas=10
	kubectl scale deployment -n crawlers load-generator-vendor-b --replicas=10
	kubectl scale deployment -n crawlers load-generator-vendor-c --replicas=10
	@echo "$(GREEN)Scaled to 10 replicas per vendor$(NC)"

scale-down: ## Scale load generators to 1 replica each
	@echo "$(GREEN)Scaling down load generators...$(NC)"
	kubectl scale deployment -n crawlers load-generator-vendor-a --replicas=1
	kubectl scale deployment -n crawlers load-generator-vendor-b --replicas=1
	kubectl scale deployment -n crawlers load-generator-vendor-c --replicas=1
	@echo "$(GREEN)Scaled to 1 replica per vendor$(NC)"

status: ## Show deployment status
	@echo "$(BLUE)Monitoring Namespace:$(NC)"
	kubectl get pods -n monitoring -o wide
	@echo ""
	@echo "$(BLUE)Crawlers Namespace:$(NC)"
	kubectl get pods -n crawlers -o wide
	@echo ""
	@echo "$(BLUE)Services:$(NC)"
	kubectl get svc -n monitoring

logs-monitoring: ## View monitoring stack logs
	kubectl logs -n monitoring -l app=prometheus --tail=50 -f

logs-crawlers: ## View crawler logs
	kubectl logs -n crawlers -l app=load-generator -c load-generator --tail=50 -f

logs-envoy: ## View Istio sidecar logs
	kubectl logs -n crawlers -l app=load-generator -c istio-proxy --tail=50 -f

port-forward-grafana: ## Port-forward Grafana (http://localhost:3000)
	@echo "$(GREEN)Port-forwarding Grafana to http://localhost:3000$(NC)"
	@echo "$(BLUE)Username: admin$(NC)"
	@echo "$(BLUE)Password: admin$(NC)"
	kubectl port-forward -n monitoring svc/grafana 3000:80

port-forward-prometheus: ## Port-forward Prometheus (http://localhost:9090)
	@echo "$(GREEN)Port-forwarding Prometheus to http://localhost:9090$(NC)"
	kubectl port-forward -n monitoring svc/prometheus 9090:9090

all: bootstrap deploy validate ## Run full deployment pipeline
	@echo ""
	@echo "$(GREEN)╔════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(GREEN)║                 Deployment Complete!                       ║$(NC)"
	@echo "$(GREEN)╚════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(BLUE)Next steps:$(NC)"
	@echo "  1. Run: make dashboards"
	@echo "  2. Open: http://localhost:3000 (Grafana)"
	@echo "  3. Scale: make scale-up"
	@echo ""

quick-start: ## Quick start for demo (bootstrap + deploy + dashboards)
	@echo "$(GREEN)Starting quick deployment...$(NC)"
	$(MAKE) bootstrap
	$(MAKE) deploy
	@echo "$(YELLOW)Waiting 30 seconds for metrics to populate...$(NC)"
	sleep 30
	$(MAKE) validate
	@echo ""
	@echo "$(GREEN)Ready! Run 'make dashboards' to view dashboards$(NC)"

