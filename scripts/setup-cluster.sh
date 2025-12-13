#!/bin/bash
# Start minikube cluster with required addons
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables if .env exists
if [ -f "$SCRIPT_DIR/../config/.env" ]; then
    source "$SCRIPT_DIR/../config/.env"
fi

# Configuration with defaults
CLUSTER_NAME="${CLUSTER_NAME:-minikube}"
MEMORY="${MEMORY:-8192}"
CPUS="${CPUS:-4}"
DRIVER="${DRIVER:-docker}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-stable}"

echo "Setting up minikube cluster..."
echo "  Profile: $CLUSTER_NAME"
echo "  Driver:  $DRIVER"
echo "  CPUs:    $CPUS"
echo "  Memory:  ${MEMORY}MB"
echo ""

# Check if cluster already exists and is running
if minikube status -p "$CLUSTER_NAME" 2>/dev/null | grep -q "Running"; then
    echo "Cluster '$CLUSTER_NAME' is already running"
    echo ""
    echo "To restart: minikube stop -p $CLUSTER_NAME && minikube start -p $CLUSTER_NAME"
    exit 0
fi

# Check if cluster exists but is stopped
if minikube status -p "$CLUSTER_NAME" 2>/dev/null | grep -q "Stopped"; then
    echo "Starting existing cluster '$CLUSTER_NAME'..."
    minikube start -p "$CLUSTER_NAME"
else
    # Create new cluster
    echo "Creating new cluster '$CLUSTER_NAME'..."
    minikube start \
        --profile="$CLUSTER_NAME" \
        --driver="$DRIVER" \
        --memory="$MEMORY" \
        --cpus="$CPUS" \
        --kubernetes-version="$KUBERNETES_VERSION" \
        --addons=ingress \
        --addons=metrics-server \
        --addons=dashboard
fi

echo ""
echo "Waiting for ingress controller to be ready..."
kubectl rollout status deployment ingress-nginx-controller \
    -n ingress-nginx --timeout=180s

# Patch ingress-nginx to LoadBalancer for minikube tunnel support
echo ""
echo "Configuring ingress for tunnel access..."
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
    -p '{"spec": {"type": "LoadBalancer"}}' 2>/dev/null || true

echo ""
echo "Cluster '$CLUSTER_NAME' is ready!"
echo ""
echo "Next steps:"
echo "  1. Run 'make dns' to configure /etc/hosts"
echo "  2. Run 'make certs' to set up certificates"
echo "  3. Run 'make tunnel' in a separate terminal"
