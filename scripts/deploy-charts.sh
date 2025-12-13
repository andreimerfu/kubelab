#!/bin/bash
# Deploy helm charts defined in the charts/ directory
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHARTS_DIR="$SCRIPT_DIR/../charts"

# Load environment variables if .env exists
if [ -f "$SCRIPT_DIR/../config/.env" ]; then
    source "$SCRIPT_DIR/../config/.env"
fi

DOMAIN="${DOMAIN:-minikube.local}"

# GitLab configuration (for ArgoCD GitOps)
GITLAB_HOST="${GITLAB_HOST:-gitlab.example.com}"
GITLAB_ORG="${GITLAB_ORG:-your-org}"
GITLAB_REPO="${GITLAB_REPO:-gitops-apps}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"

# Export variables for envsubst
export DOMAIN GITLAB_HOST GITLAB_ORG GITLAB_REPO GITLAB_TOKEN

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if yq is installed (for parsing YAML)
if ! command -v yq &> /dev/null; then
    echo -e "${RED}Error: yq is required but not installed${NC}"
    echo "Install with: brew install yq"
    exit 1
fi

# Function to deploy a single chart from a YAML document
deploy_chart() {
    local file="$1"
    local doc_index="$2"
    local is_multi_doc="$3"

    # Build yq selector for multi-doc support
    local sel=""
    if [ "$is_multi_doc" = "true" ]; then
        sel="select(document_index == $doc_index) | "
    fi

    # Extract chart configuration
    local chart_enabled=$(yq "${sel}.enabled // true" "$file" 2>/dev/null)
    local chart_repo=$(yq "${sel}.chart.repository // \"\"" "$file" 2>/dev/null)
    local chart_name=$(yq "${sel}.chart.name // \"\"" "$file" 2>/dev/null)
    local chart_version=$(yq "${sel}.chart.version // \"\"" "$file" 2>/dev/null)
    local release_name=$(yq "${sel}.release.name // \"\"" "$file" 2>/dev/null)
    local namespace=$(yq "${sel}.release.namespace // \"default\"" "$file" 2>/dev/null)

    # Ingress settings
    local ingress_enabled=$(yq "${sel}.ingress.enabled // false" "$file" 2>/dev/null)
    local ingress_name=$(yq "${sel}.ingress.name // \"\"" "$file" 2>/dev/null)
    local ingress_backend_protocol=$(yq "${sel}.ingress.backendProtocol // \"HTTP\"" "$file" 2>/dev/null)
    local ingress_service_name=$(yq "${sel}.ingress.serviceName // \"\"" "$file" 2>/dev/null)
    local ingress_service_port=$(yq "${sel}.ingress.servicePort // 80" "$file" 2>/dev/null)

    # Skip if disabled
    if [ "$chart_enabled" != "true" ]; then
        echo -e "  ${YELLOW}Skipped (disabled)${NC}"
        return 0
    fi

    # Support manifest-only deployments (no helm chart, just postInstall manifests)
    local manifest_only=false
    if [ -z "$chart_repo" ] || [ "$chart_repo" = "null" ] || [ -z "$chart_name" ] || [ "$chart_name" = "null" ]; then
        manifest_only=true
        echo -e "  ${YELLOW}Manifest-only deployment (no helm chart)${NC}"
    fi

    if [ -z "$release_name" ] || [ "$release_name" = "null" ]; then
        release_name="$chart_name"
    fi

    echo -e "  ${BLUE}Release:${NC} $release_name"
    echo -e "  ${BLUE}Namespace:${NC} $namespace"

    # Create namespace if needed
    kubectl create namespace "$namespace" 2>/dev/null || true

    # Copy mkcert CA if required (for TLS verification within cluster)
    local requires_mkcert_ca=$(yq "${sel}.requiresMkcertCA // false" "$file" 2>/dev/null)
    if [ "$requires_mkcert_ca" = "true" ]; then
        echo -e "  ${BLUE}Copying mkcert CA to namespace...${NC}"
        kubectl get configmap mkcert-ca -n kube-system -o yaml 2>/dev/null | \
            sed "s/namespace: kube-system/namespace: $namespace/" | \
            kubectl apply -f - 2>/dev/null || \
            echo -e "  ${YELLOW}Warning: mkcert-ca ConfigMap not found in kube-system${NC}"
    fi

    # Deploy helm chart if not manifest-only
    if [ "$manifest_only" != "true" ]; then
        echo -e "  ${BLUE}Chart:${NC} $chart_name"

        # Add helm repo (create a safe repo name from URL)
        local repo_name=$(echo "$chart_name" | tr '[:upper:]' '[:lower:]')
        helm repo add "$repo_name" "$chart_repo" --force-update 2>/dev/null || true

        # Build helm command
        local helm_cmd="helm upgrade --install $release_name $repo_name/$chart_name"
        helm_cmd+=" --namespace $namespace"

        if [ -n "$chart_version" ] && [ "$chart_version" != "null" ] && [ "$chart_version" != '""' ]; then
            helm_cmd+=" --version $chart_version"
        fi

        # Extract and write values to temp file
        local values_file=$(mktemp)
        yq "${sel}.values // {}" "$file" > "$values_file" 2>/dev/null

        if [ -s "$values_file" ] && [ "$(cat $values_file)" != "{}" ] && [ "$(cat $values_file)" != "null" ]; then
            helm_cmd+=" -f $values_file"
        fi

        # Run helm install/upgrade
        echo -e "  ${YELLOW}Installing...${NC}"
        if eval "$helm_cmd" --wait --timeout 10m; then
            echo -e "  ${GREEN}Helm release deployed${NC}"
        else
            echo -e "  ${RED}Helm deployment failed${NC}"
            rm -f "$values_file"
            return 1
        fi

        rm -f "$values_file"
    fi

    # Create ingress if enabled
    if [ "$ingress_enabled" = "true" ] && [ -n "$ingress_name" ] && [ "$ingress_name" != "null" ]; then
        # Build hostname: <name>.<namespace>.<domain>
        local full_hostname="${ingress_name}.${namespace}.${DOMAIN}"
        echo -e "  ${BLUE}Creating ingress:${NC} https://$full_hostname"

        # Determine service name - use specified or try to detect
        local svc_name="$ingress_service_name"
        local svc_port="$ingress_service_port"

        if [ -z "$svc_name" ] || [ "$svc_name" = "null" ]; then
            # Try to auto-detect service
            svc_name=$(kubectl get svc -n "$namespace" -l "app.kubernetes.io/instance=$release_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "$release_name")
        fi

        if [ -z "$svc_port" ] || [ "$svc_port" = "null" ] || [ "$svc_port" = "0" ]; then
            svc_port=$(kubectl get svc -n "$namespace" "$svc_name" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "80")
        fi

        # Build annotations
        local backend_annotation=""
        if [ "$ingress_backend_protocol" = "HTTPS" ]; then
            backend_annotation="nginx.ingress.kubernetes.io/backend-protocol: \"HTTPS\""
        fi

        # Create ingress manifest
        kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${release_name}-ingress
  namespace: ${namespace}
  annotations:
    cert-manager.io/cluster-issuer: mkcert-issuer
    ${backend_annotation}
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - ${full_hostname}
    secretName: ${release_name}-tls
  rules:
  - host: ${full_hostname}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${svc_name}
            port:
              number: ${svc_port}
EOF

        echo -e "  ${GREEN}Ingress ready:${NC} https://${full_hostname}"
    fi

    # Apply postInstall manifests if defined
    local post_install=$(yq "${sel}.postInstall // \"\"" "$file" 2>/dev/null)
    if [ -n "$post_install" ] && [ "$post_install" != "null" ] && [ "$post_install" != "" ]; then
        echo -e "  ${BLUE}Applying postInstall manifests...${NC}"
        local post_install_file=$(mktemp)
        # Substitute environment variables in manifests
        echo "$post_install" | envsubst '$DOMAIN $GITLAB_HOST $GITLAB_ORG $GITLAB_REPO $GITLAB_TOKEN' > "$post_install_file"
        if kubectl apply -f "$post_install_file" 2>/dev/null; then
            echo -e "  ${GREEN}PostInstall manifests applied${NC}"
        else
            echo -e "  ${YELLOW}Warning: Some postInstall manifests may have failed${NC}"
        fi
        rm -f "$post_install_file"
    fi

    echo ""
    return 0
}

# Function to process a chart file (may contain multiple docs)
deploy_chart_file() {
    local file="$1"
    local filename=$(basename "$file" .yaml)

    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}Processing: ${filename}${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo ""

    # Check if file has multiple documents (contains ---)
    # Note: grep -c returns 0 (count) with exit code 1 when no matches, so we capture output separately
    local doc_count
    doc_count=$(grep -c '^---$' "$file" 2>/dev/null) || doc_count=0

    if [ "$doc_count" -eq 0 ]; then
        # Single document
        deploy_chart "$file" 0 "false"
    else
        # Multiple documents - doc_count of --- means doc_count+1 documents
        local total_docs=$((doc_count + 1))
        for i in $(seq 0 $doc_count); do
            local name=$(yq "select(document_index == $i) | .release.name // .chart.name // \"doc-$i\"" "$file" 2>/dev/null)
            if [ -n "$name" ] && [ "$name" != "null" ]; then
                echo -e "${YELLOW}[$((i+1))/${total_docs}] $name${NC}"
                deploy_chart "$file" "$i" "true"
            fi
        done
    fi
}

# Main
echo ""
echo "========================================"
echo "  Deploying Helm Charts"
echo "========================================"
echo ""

# Update helm repos
echo "Updating helm repositories..."
helm repo update 2>/dev/null || true
echo ""

# Find and process chart files
if [ -n "$1" ]; then
    # Deploy specific chart
    chart_file="$CHARTS_DIR/$1.yaml"
    if [ -f "$chart_file" ]; then
        deploy_chart_file "$chart_file"
    else
        echo -e "${RED}Chart file not found: $chart_file${NC}"
        echo ""
        echo "Available charts:"
        for f in "$CHARTS_DIR"/*.yaml; do
            [ -f "$f" ] && echo "  - $(basename "$f" .yaml)"
        done
        exit 1
    fi
else
    # Deploy all enabled charts
    for chart_file in "$CHARTS_DIR"/*.yaml; do
        if [ -f "$chart_file" ]; then
            deploy_chart_file "$chart_file"
        fi
    done
fi

echo "========================================"
echo "  Deployment Complete"
echo "========================================"
echo ""
echo "Check status with: make status"
echo "Remember: 'make tunnel' must be running for ingress access"
