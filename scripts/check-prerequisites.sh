#!/bin/bash
# Check all prerequisites for minikube development environment
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Checking prerequisites..."
echo ""

MISSING_TOOLS=()
WARNINGS=()

# Required tools
REQUIRED_TOOLS=("minikube" "helm" "kubectl" "mkcert" "docker" "yq")

# Optional tools (installed automatically if missing)
OPTIONAL_TOOLS=("dnsmasq")

for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" &> /dev/null; then
        VERSION=$($tool version --short 2>/dev/null || $tool version 2>/dev/null | head -1 || echo "installed")
        echo -e "${GREEN}✓${NC} $tool: $VERSION"
    else
        echo -e "${RED}✗${NC} $tool: not found"
        MISSING_TOOLS+=("$tool")
    fi
done

echo ""

# Check Docker is running
if command -v docker &> /dev/null; then
    if docker info &> /dev/null; then
        echo -e "${GREEN}✓${NC} Docker daemon is running"
    else
        echo -e "${RED}✗${NC} Docker is installed but not running"
        WARNINGS+=("Start Docker Desktop before proceeding")
    fi
fi

# Check mkcert CA is installed
if command -v mkcert &> /dev/null; then
    CAROOT=$(mkcert -CAROOT 2>/dev/null)
    if [ -f "$CAROOT/rootCA.pem" ]; then
        echo -e "${GREEN}✓${NC} mkcert CA is installed at $CAROOT"
    else
        echo -e "${YELLOW}!${NC} mkcert CA not installed"
        WARNINGS+=("Run 'mkcert -install' to install the CA")
    fi
fi

echo ""

# Summary
if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo -e "${RED}Missing required tools:${NC}"
    echo "  brew install ${MISSING_TOOLS[*]}"
    echo ""
fi

if [ ${#WARNINGS[@]} -ne 0 ]; then
    echo -e "${YELLOW}Warnings:${NC}"
    for warning in "${WARNINGS[@]}"; do
        echo "  - $warning"
    done
    echo ""
fi

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    exit 1
fi

if [ ${#WARNINGS[@]} -ne 0 ]; then
    echo -e "${YELLOW}Please resolve warnings before proceeding.${NC}"
    exit 1
fi

echo -e "${GREEN}All prerequisites satisfied!${NC}"
