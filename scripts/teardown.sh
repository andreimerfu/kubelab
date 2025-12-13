#!/bin/bash
# Clean up minikube development environment
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables if .env exists
if [ -f "$SCRIPT_DIR/../config/.env" ]; then
    source "$SCRIPT_DIR/../config/.env"
fi

CLUSTER_NAME="${CLUSTER_NAME:-minikube}"
DOMAIN="${DOMAIN:-minikube.local}"
RESOLVER_DIR="/etc/resolver"
DNSMASQ_CONF_DIR="/opt/homebrew/etc/dnsmasq.d"
[ -d "$DNSMASQ_CONF_DIR" ] || DNSMASQ_CONF_DIR="/usr/local/etc/dnsmasq.d"

echo "Tearing down minikube development environment..."
echo ""

# Check if cluster exists
if minikube status -p "$CLUSTER_NAME" &>/dev/null; then
    echo "Deleting minikube cluster '$CLUSTER_NAME'..."
    minikube delete -p "$CLUSTER_NAME"
    echo "Cluster deleted."
else
    echo "Cluster '$CLUSTER_NAME' does not exist, skipping..."
fi

echo ""

# Remove DNS configuration
echo "Removing DNS configuration..."

# Remove dnsmasq config
if [ -f "$DNSMASQ_CONF_DIR/minikube.conf" ]; then
    sudo rm -f "$DNSMASQ_CONF_DIR/minikube.conf"
    echo "Removed dnsmasq config"
    sudo brew services restart dnsmasq 2>/dev/null || brew services restart dnsmasq 2>/dev/null || true
fi

# Remove resolver
if [ -f "$RESOLVER_DIR/$DOMAIN" ]; then
    sudo rm -f "$RESOLVER_DIR/$DOMAIN"
    echo "Removed resolver for $DOMAIN"
fi

# Flush DNS cache
sudo dscacheutil -flushcache 2>/dev/null || true
sudo killall -HUP mDNSResponder 2>/dev/null || true

echo ""
echo "Teardown complete!"
echo ""
echo "Note: mkcert CA remains installed in your system trust store."
echo "      To remove it: mkcert -uninstall"
echo ""
echo "Note: dnsmasq remains installed but minikube config removed."
echo "      To fully remove: brew uninstall dnsmasq"
