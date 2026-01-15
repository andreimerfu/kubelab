.PHONY: all prerequisites cluster dns certs charts dashboards tunnel docker-bridge dashboard status creds docker-hosts docker-patch clean help

SHELL := /bin/bash
DOMAIN ?= minikube.local
CLUSTER_NAME ?= minikube
SCRIPTS_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))/scripts
CHARTS_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))/charts

# Default target: full setup
all: prerequisites cluster dns certs
	@echo ""
	@echo "============================================"
	@echo "  Setup complete!"
	@echo "============================================"
	@echo ""
	@echo "Wildcard DNS: *.$(DOMAIN) → 127.0.0.1"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Run 'make tunnel' in a separate terminal"
	@echo "  2. Deploy charts: make charts"
	@echo "  3. Open dashboard: make dashboard"
	@echo ""

# Check all prerequisites
prerequisites:
	@chmod +x $(SCRIPTS_DIR)/*.sh
	@$(SCRIPTS_DIR)/check-prerequisites.sh

# Start minikube cluster
cluster: prerequisites
	@CLUSTER_NAME=$(CLUSTER_NAME) $(SCRIPTS_DIR)/setup-cluster.sh

# Configure wildcard DNS using dnsmasq
dns:
	@DOMAIN=$(DOMAIN) $(SCRIPTS_DIR)/setup-dns.sh

# Set up mkcert + cert-manager
certs: cluster
	@$(SCRIPTS_DIR)/setup-certificates.sh

# Deploy all helm charts defined in charts/
charts: certs
	@DOMAIN=$(DOMAIN) $(SCRIPTS_DIR)/deploy-charts.sh
	@$(SCRIPTS_DIR)/deploy-dashboards.sh

# Deploy Grafana dashboards from dashboards/
dashboards:
	@$(SCRIPTS_DIR)/deploy-dashboards.sh

# Deploy a specific chart (e.g., make chart-opensearch)
chart-%:
	@DOMAIN=$(DOMAIN) $(SCRIPTS_DIR)/deploy-charts.sh $*

# List available charts
charts-list:
	@echo "Available charts:"
	@for f in $(CHARTS_DIR)/*.yaml; do \
		name=$$(basename $$f .yaml); \
		enabled=$$(yq '.enabled // true' $$f 2>/dev/null); \
		if [ "$$enabled" = "true" ]; then \
			echo "  $$name (enabled)"; \
		else \
			echo "  $$name (disabled)"; \
		fi \
	done

# Start minikube tunnel (run in separate terminal)
tunnel:
	@echo "Starting minikube tunnel..."
	@echo "This requires sudo and must stay running."
	@echo "Press Ctrl+C to stop."
	@echo ""
	@minikube tunnel -p $(CLUSTER_NAME)

# Bridge minikube services to Docker containers (run in separate terminal)
# Required when using Docker Compose with minikube services
docker-bridge:
	@$(SCRIPTS_DIR)/docker-bridge.sh

# Open Kubernetes dashboard
dashboard:
	@minikube dashboard -p $(CLUSTER_NAME)

# Show cluster status
status:
	@echo "=== Minikube Status ==="
	@minikube status -p $(CLUSTER_NAME) 2>/dev/null || echo "Cluster not running"
	@echo ""
	@echo "=== Nodes ==="
	@kubectl get nodes 2>/dev/null || echo "Cannot connect to cluster"
	@echo ""
	@echo "=== Ingress Controller ==="
	@kubectl get pods -n ingress-nginx 2>/dev/null || echo "Ingress not installed"
	@echo ""
	@echo "=== Cert-Manager ==="
	@kubectl get pods -n cert-manager 2>/dev/null || echo "Cert-manager not installed"
	@echo ""
	@echo "=== Helm Releases ==="
	@helm list -A 2>/dev/null || echo "No helm releases"
	@echo ""
	@echo "=== Ingresses ==="
	@kubectl get ingress -A 2>/dev/null || echo "No ingresses found"
	@echo ""
	@echo "=== Certificates ==="
	@kubectl get certificates -A 2>/dev/null || echo "No certificates found"

# Show service connection details and credentials
creds:
	@DOMAIN=$(DOMAIN) $(SCRIPTS_DIR)/show-connections.sh

# Show extra_hosts snippet for Docker Compose
docker-hosts:
	@DOMAIN=$(DOMAIN) $(SCRIPTS_DIR)/docker-hosts.sh

# Patch a docker-compose.yml to add extra_hosts (requires yq)
# Usage: make docker-patch FILE=/path/to/docker-compose.yml
docker-patch:
ifndef FILE
	$(error Usage: make docker-patch FILE=/path/to/docker-compose.yml)
endif
	@DOMAIN=$(DOMAIN) $(SCRIPTS_DIR)/docker-patch.sh $(FILE)

# Start fresh - stop cluster but keep config
stop:
	@echo "Stopping minikube cluster..."
	@minikube stop -p $(CLUSTER_NAME) || true

# Start existing cluster
start:
	@echo "Starting minikube cluster..."
	@minikube start -p $(CLUSTER_NAME)
	@echo ""
	@echo "Remember to run 'make tunnel' in a separate terminal"

# Remove everything
clean:
	@echo "This will delete the minikube cluster and remove DNS config."
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@$(SCRIPTS_DIR)/teardown.sh

# Force clean without confirmation
clean-force:
	@$(SCRIPTS_DIR)/teardown.sh

# Show help
help:
	@echo "Minikube Development Environment"
	@echo "================================="
	@echo ""
	@echo "Domain pattern: <name>.<namespace>.$(DOMAIN)"
	@echo ""
	@echo "Quick Start:"
	@echo "  make all        - Full setup (cluster, DNS, certs)"
	@echo "  make tunnel     - Start tunnel (run in separate terminal)"
	@echo "  make charts     - Deploy all helm charts"
	@echo "  make dashboard  - Open Kubernetes dashboard"
	@echo ""
	@echo "Setup Targets:"
	@echo "  prerequisites   - Check required tools are installed"
	@echo "  cluster         - Start minikube with addons"
	@echo "  dns             - Configure wildcard DNS (*.$(DOMAIN))"
	@echo "  certs           - Install cert-manager with mkcert CA"
	@echo ""
	@echo "Chart Management:"
	@echo "  charts          - Deploy all charts and dashboards"
	@echo "  chart-<name>    - Deploy specific chart (e.g., make chart-opensearch)"
	@echo "  charts-list     - List available charts"
	@echo "  dashboards      - Deploy Grafana dashboards only"
	@echo ""
	@echo "Management:"
	@echo "  status          - Show cluster and services status"
	@echo "  creds           - Show service URLs and credentials"
	@echo "  dashboard       - Open Kubernetes dashboard"
	@echo "  start           - Start existing cluster"
	@echo "  stop            - Stop cluster (keeps data)"
	@echo "  clean           - Delete cluster and DNS config"
	@echo ""
	@echo "Docker Integration:"
	@echo "  docker-bridge   - Bridge ports for Docker (run with tunnel)"
	@echo "  docker-hosts    - Show extra_hosts snippet for docker-compose"
	@echo "  docker-patch    - Patch compose file (make docker-patch FILE=...)"
	@echo ""
	@echo "Variables:"
	@echo "  DOMAIN=$(DOMAIN)"
	@echo "  CLUSTER_NAME=$(CLUSTER_NAME)"
	@echo ""
	@echo "Examples:"
	@echo "  make all && make charts"
	@echo "  make chart-opensearch"
