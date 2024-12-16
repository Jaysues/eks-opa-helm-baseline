#!/bin/bash

# deploy-constraints.sh
set -e  # Exit on any error

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting constraint deployment script...${NC}"

# Function to check if helm is installed
check_helm() {
    if ! command -v helm &> /dev/null; then
        echo -e "${RED}Error: helm is not installed${NC}"
        exit 1
    fi
}

# Function to check if kubectl is installed and can access the cluster
check_kubectl() {
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
        exit 1
    fi
}

# Function to check if namespace exists, create if it doesn't
ensure_namespace() {
    local namespace=$1
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        echo -e "${YELLOW}Creating namespace: $namespace${NC}"
        kubectl create namespace "$namespace"
    fi
}

# Main deployment process
main() {
    # Check prerequisites
    check_helm
    check_kubectl

    # Ensure gatekeeper-system namespace exists
    ensure_namespace "gatekeeper-system"

    # Deploy constraints with all values files
    echo -e "${GREEN}Deploying constraints with all values...${NC}"
    helm upgrade --install eks-opa-policy-constraints \
        "../" \
        -f "../values.yaml" \
        -f "../environment/dev/values.yaml" \
        -f "../customer/customer-1/values.yaml" \
        -n "gatekeeper-system" \
        --wait

    # Verify deployment
    echo -e "${GREEN}Verifying constraint deployment...${NC}"
    kubectl get constraints -n gatekeeper-system

    echo -e "${GREEN}Deployment complete!${NC}"
}

# Run the main function
main