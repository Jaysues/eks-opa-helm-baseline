#!/bin/bash

# verify-constraints.sh
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Create logs directory if it doesn't exist
LOGS_DIR="constraint_verification_logs"
mkdir -p "$LOGS_DIR"

# Create timestamp for log file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOGS_DIR/constraint_verification_$TIMESTAMP.log"

# Function to log messages to both console and file
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

log "${YELLOW}Starting constraint verification...${NC}"
log "Timestamp: $(date)"
log "----------------------------------------"

# Get all constraints
log "\n${GREEN}Listing all constraints:${NC}"
kubectl get constraints -n gatekeeper-system | tee -a "$LOG_FILE"

# Check constraint status
log "\n${GREEN}Checking constraint status:${NC}"
kubectl get constraints -n gatekeeper-system -o custom-columns=NAME:.metadata.name,STATUS:.status.totalViolations,ENFORCEMENT:.spec.enforcementAction | tee -a "$LOG_FILE"

# Detailed verification of each constraint
log "\n${GREEN}Detailed constraint verification:${NC}"
for constraint in $(kubectl get constraints -n gatekeeper-system -o name); do
    log "\n${YELLOW}Verifying $constraint:${NC}"
    
    # Check enforcement action
    enforcement=$(kubectl get $constraint -n gatekeeper-system -o jsonpath='{.spec.enforcementAction}')
    log "Enforcement Action: $enforcement"
    
    # Check excluded namespaces
    log "Excluded Namespaces:"
    kubectl get $constraint -n gatekeeper-system -o jsonpath='{.spec.match.excludedNamespaces}' | jq '.' >> "$LOG_FILE" 2>&1 || log "None specified"
    
    # Check parameters
    log "Parameters:"
    kubectl get $constraint -n gatekeeper-system -o jsonpath='{.spec.parameters}' | jq '.' >> "$LOG_FILE" 2>&1 || log "No parameters specified"
    
    # Check status
    log "Status:"
    kubectl get $constraint -n gatekeeper-system -o jsonpath='{.status}' | jq '.' >> "$LOG_FILE" 2>&1 || log "No status information"
    
    log "----------------------------------------"
done

# Add summary information
log "\n${GREEN}Verification Summary:${NC}"
log "Total Constraints: $(kubectl get constraints -n gatekeeper-system -o name | wc -l)"
log "Constraints with Violations: $(kubectl get constraints -n gatekeeper-system -o json | jq '.items[] | select(.status.totalViolations > 0) | .metadata.name' | wc -l)"

# Add audit logs
log "\n${GREEN}Recent Gatekeeper Audit Logs:${NC}"
kubectl logs -n gatekeeper-system -l control-plane=audit-controller --tail=50 >> "$LOG_FILE" 2>&1

echo -e "${GREEN}Verification complete! Results saved to: $LOG_FILE${NC}"