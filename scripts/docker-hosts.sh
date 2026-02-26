#!/bin/bash
# Output extra_hosts snippet for Docker Compose
# These entries allow containers to resolve minikube services via host-gateway

DOMAIN="${DOMAIN:-minikube.local}"

cat << EOF
# Add this to each service in your docker-compose.yml
# These entries map minikube hostnames to your host machine

extra_hosts:
  - "postgresql.$DOMAIN:host-gateway"
  - "redis.$DOMAIN:host-gateway"
  - "opensearch.opensearch.$DOMAIN:host-gateway"
  - "dashboards.opensearch.$DOMAIN:host-gateway"
  - "grafana.monitoring.$DOMAIN:host-gateway"
  - "console.argocd.$DOMAIN:host-gateway"
  - "auth.dex.$DOMAIN:host-gateway"
  - "nats.$DOMAIN:host-gateway"
EOF
