#!/bin/bash
# Patch a docker-compose.yml to add extra_hosts for minikube services
# Usage: ./docker-patch.sh /path/to/docker-compose.yml

set -e

DOMAIN="${DOMAIN:-minikube.local}"
FILE="$1"

if [ -z "$FILE" ]; then
    echo "Usage: $0 <docker-compose.yml>"
    echo ""
    echo "This script adds extra_hosts entries to all services in your"
    echo "docker-compose.yml so containers can reach minikube services."
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo "Error: File not found: $FILE"
    exit 1
fi

# Check for yq
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed."
    echo "Install with: brew install yq"
    exit 1
fi

# Define the hosts to add
HOSTS=(
    "postgresql.$DOMAIN:host-gateway"
    "redis.$DOMAIN:host-gateway"
    "opensearch.opensearch.$DOMAIN:host-gateway"
    "dashboards.opensearch.$DOMAIN:host-gateway"
    "grafana.monitoring.$DOMAIN:host-gateway"
    "console.argocd.$DOMAIN:host-gateway"
    "auth.dex.$DOMAIN:host-gateway"
)

echo "Patching: $FILE"
echo "Adding extra_hosts for minikube services..."

# Build yq expression to add all hosts
for host in "${HOSTS[@]}"; do
    yq eval -i "(.services[] | .extra_hosts) |= (. // [] | . + [\"$host\"] | unique)" "$FILE"
done

echo "Done! Services can now reach:"
for host in "${HOSTS[@]}"; do
    hostname="${host%:*}"
    echo "  - $hostname"
done
