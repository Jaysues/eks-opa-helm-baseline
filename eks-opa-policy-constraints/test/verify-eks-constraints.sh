#!/bin/bash
# verify-eks-constraints.sh

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOGS_DIR="eks_constraint_verification_logs"
mkdir -p "$LOGS_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOGS_DIR/eks_verification_$TIMESTAMP.log"

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

verify_eks_specific() {
    log "${YELLOW}Verifying EKS-specific components...${NC}"
    
    # Check EKS version and cluster info
    log "\nCluster Info:"
    kubectl cluster-info | tee -a "$LOG_FILE"
    
    # Check EKS node groups
    log "\nNode Groups:"
    kubectl get nodes --show-labels | tee -a "$LOG_FILE"
    
    # Check AWS auth configmap
    log "\nAWS auth configuration:"
    kubectl get configmap aws-auth -n kube-system -o yaml | tee -a "$LOG_FILE"
}

verify_constraints() {
    log "${YELLOW}Verifying constraints...${NC}"
    
    # Get all constraints
    log "\n${GREEN}Listing all constraints:${NC}"
    kubectl get constraints -n gatekeeper-system | tee -a "$LOG_FILE"
    
    # Check constraint status
    log "\n${GREEN}Checking constraint status:${NC}"
    kubectl get constraints -n gatekeeper-system -o custom-columns=NAME:.metadata.name,STATUS:.status.totalViolations,ENFORCEMENT:.spec.enforcementAction | tee -a "$LOG_FILE"
    
    # Detailed verification of each constraint
    for constraint in $(kubectl get constraints -n gatekeeper-system -o name); do
        log "\n${YELLOW}Verifying $constraint:${NC}"
        kubectl get $constraint -n gatekeeper-system -o yaml >> "$LOG_FILE"
    done
}

verify_gatekeeper() {
    log "${YELLOW}Verifying Gatekeeper status...${NC}"
    
    # Check Gatekeeper pods
    log "\nGatekeeper pods:"
    kubectl get pods -n gatekeeper-system | tee -a "$LOG_FILE"
    
    # Check Gatekeeper logs
    log "\nGatekeeper audit logs:"
    kubectl logs -n gatekeeper-system -l control-plane=audit-controller --tail=50 >> "$LOG_FILE"
}

main() {
    log "${GREEN}Starting EKS constraint verification...${NC}"
    
    # Verify EKS-specific components
    verify_eks_specific
    
    # Verify constraints
    verify_constraints
    
    # Verify Gatekeeper
    verify_gatekeeper
    
    log "${GREEN}Verification complete! Results saved to: $LOG_FILE${NC}"
}

main