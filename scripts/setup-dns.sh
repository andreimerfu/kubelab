#!/bin/bash
# Configure wildcard DNS for minikube using dnsmasq
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables if .env exists
if [ -f "$SCRIPT_DIR/../config/.env" ]; then
    source "$SCRIPT_DIR/../config/.env"
fi

DOMAIN="${DOMAIN:-minikube.local}"
RESOLVER_DIR="/etc/resolver"
DNSMASQ_CONF_DIR="/opt/homebrew/etc/dnsmasq.d"
# Fallback for Intel Macs
[ -d "$DNSMASQ_CONF_DIR" ] || DNSMASQ_CONF_DIR="/usr/local/etc/dnsmasq.d"

echo "Setting up wildcard DNS for *.${DOMAIN}..."
echo ""

# Check if dnsmasq is installed
if ! command -v dnsmasq &> /dev/null; then
    echo "Installing dnsmasq..."
    brew install dnsmasq
fi

# Ensure dnsmasq.d directory exists
sudo mkdir -p "$DNSMASQ_CONF_DIR"

# Create dnsmasq config for minikube
echo "Configuring dnsmasq for *.${DOMAIN} → 127.0.0.1..."
sudo tee "$DNSMASQ_CONF_DIR/minikube.conf" > /dev/null <<EOF
# Minikube local development DNS
# All *.${DOMAIN} resolves to 127.0.0.1
address=/${DOMAIN}/127.0.0.1
EOF

# Ensure main dnsmasq.conf includes the conf-dir
DNSMASQ_MAIN_CONF="$(dirname "$DNSMASQ_CONF_DIR")/dnsmasq.conf"
if [ -f "$DNSMASQ_MAIN_CONF" ]; then
    if ! grep -q "conf-dir=$DNSMASQ_CONF_DIR" "$DNSMASQ_MAIN_CONF" 2>/dev/null; then
        echo "conf-dir=$DNSMASQ_CONF_DIR/,*.conf" | sudo tee -a "$DNSMASQ_MAIN_CONF" > /dev/null
    fi
fi

# Restart dnsmasq
echo "Starting dnsmasq service..."
sudo brew services restart dnsmasq 2>/dev/null || brew services restart dnsmasq

# Create resolver for macOS
echo "Configuring macOS resolver for .${DOMAIN}..."
sudo mkdir -p "$RESOLVER_DIR"

# Extract TLD for resolver filename (e.g., "minikube.local" -> "minikube.local")
sudo tee "$RESOLVER_DIR/${DOMAIN}" > /dev/null <<EOF
nameserver 127.0.0.1
EOF

# Flush DNS cache
echo "Flushing DNS cache..."
sudo dscacheutil -flushcache 2>/dev/null || true
sudo killall -HUP mDNSResponder 2>/dev/null || true

echo ""
echo "DNS configuration complete!"
echo ""
echo "All *.${DOMAIN} now resolves to 127.0.0.1"
echo ""

# Configure CoreDNS for in-cluster resolution of minikube.local
echo "Configuring CoreDNS for in-cluster *.${DOMAIN} resolution..."

# Get ingress controller ClusterIP
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")

if [ -n "$INGRESS_IP" ]; then
    # Update CoreDNS to resolve minikube.local to ingress
    cat <<COREDNS_EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  minikube.server: |
    ${DOMAIN} {
        hosts {
           ${INGRESS_IP} auth.dex.${DOMAIN}
           ${INGRESS_IP} console.argocd.${DOMAIN}
           fallthrough
        }
        whoami
    }
COREDNS_EOF

    # Patch CoreDNS to include custom hosts for minikube.local
    kubectl get configmap coredns -n kube-system -o yaml | \
    sed "s|fallthrough\n        }|fallthrough\n        }\n        import /etc/coredns/custom/*.server|" | \
    kubectl apply -f - 2>/dev/null || true

    # Alternative: directly add hosts entries to CoreDNS
    CURRENT_HOSTS=$(kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' | grep -A5 "hosts {" | head -6)
    if ! echo "$CURRENT_HOSTS" | grep -q "${DOMAIN}"; then
        echo "Adding ${DOMAIN} entries to CoreDNS hosts..."
        kubectl get configmap coredns -n kube-system -o json | \
        jq --arg ip "$INGRESS_IP" --arg domain "$DOMAIN" '
          .data.Corefile |= gsub(
            "(?<pre>hosts \\{[^}]*host.minikube.internal)";
            "\(.pre)\n           \($ip) auth.dex.\($domain)\n           \($ip) console.argocd.\($domain)"
          )
        ' | kubectl apply -f - 2>/dev/null || {
            # Fallback: recreate the configmap
            cat <<COREFILE_EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        log
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        hosts {
           0.250.250.254 host.minikube.internal
           ${INGRESS_IP} auth.dex.${DOMAIN}
           ${INGRESS_IP} console.argocd.${DOMAIN}
           fallthrough
        }
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30 {
           disable success cluster.local
           disable denial cluster.local
        }
        loop
        reload
        loadbalance
    }
COREFILE_EOF
        }
        kubectl rollout restart deployment coredns -n kube-system
        echo "CoreDNS updated for in-cluster ${DOMAIN} resolution"
    fi
else
    echo "Warning: ingress-nginx not found, skipping CoreDNS configuration"
    echo "Run 'make dns' after deploying ingress-nginx to configure in-cluster DNS"
fi

echo ""
echo "Examples:"
echo "  opensearch.opensearch.${DOMAIN}"
echo "  dashboard.kubernetes.${DOMAIN}"
echo "  myapp.default.${DOMAIN}"
echo ""
echo "Test with: ping test.${DOMAIN}"
