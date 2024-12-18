#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print status messages
print_status() {
    echo -e "${YELLOW}==> ${1}${NC}"
}

# Function to print error messages
print_error() {
    echo -e "${RED}Error: ${1}${NC}"
}

# Check prerequisites
print_status "Checking prerequisites..."

# Check for kubectl
if ! command_exists kubectl; then
    print_error "kubectl is not installed"
    exit 1
fi

# Check for helm
if ! command_exists helm; then
    print_error "helm is not installed"
    exit 1
fi

# Check if k3s cluster is running
if ! kubectl cluster-info &>/dev/null; then
    print_error "Cannot connect to K3s cluster"
    exit 1
fi

# Check if gatekeeper-system namespace exists
if ! kubectl get ns gatekeeper-system &>/dev/null; then
    print_error "Gatekeeper is not installed. Please install Gatekeeper first."
    exit 1
fi

# Deploy templates
print_status "Deploying constraint templates..."

# Try to deploy templates and catch errors
if ! helm upgrade --install eks-opa-policy-templates ../eks-opa-policy-templates --debug\
    --namespace gatekeeper-system \
    --force; then
    print_error "Failed to deploy templates. Check the Helm release logs for more details."
    exit 1
fi

# Verify templates
print_status "Verifying templates..."
TEMPLATES=(
    "eksallowedcapabilities"
    "eksallowedimages"
    "eksnoprivilegeescalation"
    "eksenforceprobes"
    "eksminimisewildcard"
    "eksblockdefaultnamespace"
    "eksblockautomounttoken"
    "ekscontainernoprivilege"
    "eksreadonlyfilesystem"
    "ekslimitsensitiveverbs"
    "eksenforcesecretaccess"
    "eksforbiddensysctl"
    "ekssecretsasfiles"
    "eksnetworkpolicyexists"
    "ekspsphostnamespace"
    "ekspsphostfilesystem"
    "eksadminaccess"
    "eksrestrictdefaultsa"
)

FAILED_TEMPLATES=()

for template in "${TEMPLATES[@]}"; do
    if kubectl get constrainttemplate "$template" -n gatekeeper-system &>/dev/null; then
        echo -e "${GREEN}✓ Template $template installed successfully${NC}"
        
        # Verify template is ready
        if kubectl wait --for=condition=ready constrainttemplate "$template" -n gatekeeper-system --timeout=1s &>/dev/null; then
            echo -e "${GREEN}✓ Template $template is ready${NC}"
        else
            print_error "Template $template is not ready"
            FAILED_TEMPLATES+=("$template")
        fi
    else
        print_error "Template $template not found"
        FAILED_TEMPLATES+=("$template")
    fi
done

# Final status
if [ ${#FAILED_TEMPLATES[@]} -eq 0 ]; then
    echo -e "\n${GREEN}All templates validated successfully!${NC}"
    exit 0
else
    echo -e "\n${RED}The following templates failed validation:${NC}"
    printf '%s\n' "${FAILED_TEMPLATES[@]}"
    exit 1
fi