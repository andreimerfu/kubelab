#!/bin/bash
# Set up mkcert + cert-manager for automatic TLS certificates
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"

echo "Setting up certificate infrastructure..."
echo ""

# Check mkcert is installed
if ! command -v mkcert &> /dev/null; then
    echo "Error: mkcert is not installed"
    echo "Install with: brew install mkcert"
    exit 1
fi

# Get mkcert CA root
CAROOT=$(mkcert -CAROOT)

# Ensure mkcert CA exists
if [ ! -f "$CAROOT/rootCA.pem" ]; then
    echo "Installing mkcert CA into system trust store..."
    mkcert -install
    echo ""
fi

echo "Using mkcert CA from: $CAROOT"
echo ""

# Install cert-manager via Helm
if kubectl get namespace cert-manager &>/dev/null; then
    echo "cert-manager namespace already exists"
else
    echo "Installing cert-manager..."
    helm repo add jetstack https://charts.jetstack.io --force-update
    helm repo update jetstack

    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --set crds.enabled=true \
        --wait

    echo "cert-manager installed successfully"
fi

echo ""

# Wait for cert-manager to be ready
echo "Waiting for cert-manager webhook to be ready..."
kubectl rollout status deployment cert-manager-webhook \
    -n cert-manager --timeout=120s

echo ""

# Create secret from mkcert CA
echo "Creating mkcert CA secret in cert-manager namespace..."
kubectl -n cert-manager delete secret mkcert-ca-key-pair --ignore-not-found

# Check if key file exists (it should in default mkcert setup)
if [ -f "$CAROOT/rootCA-key.pem" ]; then
    kubectl -n cert-manager create secret tls mkcert-ca-key-pair \
        --key="$CAROOT/rootCA-key.pem" \
        --cert="$CAROOT/rootCA.pem"
else
    echo "Warning: mkcert CA key not found at $CAROOT/rootCA-key.pem"
    echo "This might happen if mkcert was installed differently."
    echo "Creating secret with cert only (signing won't work)..."
    kubectl -n cert-manager create secret generic mkcert-ca-key-pair \
        --from-file=tls.crt="$CAROOT/rootCA.pem"
fi

echo ""

# Apply ClusterIssuer
echo "Creating mkcert ClusterIssuer..."
kubectl apply -f "$MANIFESTS_DIR/cert-manager/mkcert-clusterissuer.yaml"

echo ""

# Create shared CA ConfigMap for in-cluster TLS verification
echo "Creating shared mkcert CA ConfigMap..."
kubectl create configmap mkcert-ca \
    --from-file=ca.crt="$CAROOT/rootCA.pem" \
    -n kube-system \
    --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Certificate infrastructure ready!"
echo ""
echo "Usage: Add this annotation to your Ingress resources:"
echo "  cert-manager.io/cluster-issuer: mkcert-issuer"
echo ""
echo "Example Ingress spec:"
echo "  tls:"
echo "  - hosts:"
echo "    - myapp.test"
echo "    secretName: myapp-tls  # cert-manager creates this automatically"
