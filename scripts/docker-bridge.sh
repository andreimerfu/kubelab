#!/bin/bash
# Bridge minikube services to Docker containers
#
# Problem: minikube tunnel binds to 127.0.0.1, but Docker containers
# access the host via host-gateway (192.168.65.254 or similar).
#
# Solution: Use socat to forward from 0.0.0.0 to 127.0.0.1

set -e

# Check for socat
if ! command -v socat &> /dev/null; then
    echo "Error: socat is required but not installed."
    echo "Install with: brew install socat"
    exit 1
fi

# Ports to bridge (minikube services exposed via tunnel)
PORTS=(
    "5432"   # PostgreSQL RW
    "5433"   # PostgreSQL RO
    "6379"   # Redis
    "9200"   # OpenSearch
)

cleanup() {
    echo ""
    echo "Stopping port bridges..."
    pkill -f "socat.*TCP-LISTEN" 2>/dev/null || true
    exit 0
}

trap cleanup SIGINT SIGTERM

echo "============================================"
echo "  Docker Bridge for Minikube Services"
echo "============================================"
echo ""
echo "This bridges minikube services to Docker containers."
echo "Keep this running alongside 'make tunnel'."
echo ""

# Kill any existing socat processes for these ports
for port in "${PORTS[@]}"; do
    pkill -f "socat.*TCP-LISTEN:$port" 2>/dev/null || true
done

# Start socat for each port
for port in "${PORTS[@]}"; do
    echo "Bridging port $port (0.0.0.0:$port → 127.0.0.1:$port)"
    socat TCP-LISTEN:$port,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:$port &
done

echo ""
echo "Bridges active. Press Ctrl+C to stop."
echo ""

# Wait for all background jobs
wait
