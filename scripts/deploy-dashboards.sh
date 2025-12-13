#!/bin/bash
# Deploy Grafana dashboards from the dashboards/ directory
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARDS_DIR="$SCRIPT_DIR/../dashboards"
NAMESPACE="monitoring"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "========================================"
echo "  Deploying Grafana Dashboards"
echo "========================================"
echo ""

# Check if dashboards directory exists
if [ ! -d "$DASHBOARDS_DIR" ]; then
    echo -e "${YELLOW}No dashboards directory found${NC}"
    exit 0
fi

# Find and deploy all JSON dashboard files
for dashboard_file in "$DASHBOARDS_DIR"/*.json; do
    if [ -f "$dashboard_file" ]; then
        filename=$(basename "$dashboard_file" .json)
        configmap_name="grafana-dashboard-${filename}"

        echo -e "${BLUE}Deploying:${NC} $filename"

        # Delete existing ConfigMap if it exists
        kubectl delete configmap "$configmap_name" -n "$NAMESPACE" 2>/dev/null || true

        # Create ConfigMap from JSON file
        kubectl create configmap "$configmap_name" \
            --from-file="${filename}.json=${dashboard_file}" \
            -n "$NAMESPACE"

        # Add label so Grafana sidecar picks it up
        kubectl label configmap "$configmap_name" -n "$NAMESPACE" grafana_dashboard=1

        echo -e "${GREEN}  Created ConfigMap:${NC} $configmap_name"
    fi
done

echo ""
echo -e "${GREEN}Dashboards deployed successfully${NC}"
echo ""
echo "Note: Grafana will automatically load dashboards via sidecar."
echo "If dashboards don't appear, restart Grafana: kubectl rollout restart -n monitoring deploy/vm-grafana"
