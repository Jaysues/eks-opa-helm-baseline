#!/bin/bash
# test-exemptions.sh

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOGS_DIR="exemption_test_logs"
mkdir -p "$LOGS_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOGS_DIR/exemption_tests_$TIMESTAMP.log"

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

log_cmd() {
    echo -e "\n$ $1" >> "$LOG_FILE"
    eval "$1" 2>&1 | tee -a "$LOG_FILE"
}

create_test_cases() {
    log "${YELLOW}Creating test resources...${NC}"

    # Create test namespace
    log "\nCreating test namespace:"
    cat <<EOF | kubectl apply -f - 2>&1 | tee -a "$LOG_FILE"
apiVersion: v1
kind: Namespace
metadata:
  name: exemption-test
  labels:
    test: "true"
EOF

    # Non-exempted test cases
    log "\nCreating non-exempted test resources:"
    cat <<EOF | kubectl apply -f - 2>&1 | tee -a "$LOG_FILE"
apiVersion: v1
kind: Pod
metadata:
  name: capability-test-pod
  namespace: exemption-test
spec:
  containers:
  - name: test-container
    image: nginx:latest
    securityContext:
      capabilities:
        add: ["NET_ADMIN"]
---
apiVersion: v1
kind: Pod
metadata:
  name: image-test-pod
  namespace: exemption-test
spec:
  containers:
  - name: test-container
    image: docker.io/nginx:latest
---
apiVersion: v1
kind: Pod
metadata:
  name: privilege-test-pod
  namespace: exemption-test
spec:
  containers:
  - name: privileged-container
    image: nginx:latest
    securityContext:
      privileged: true
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: test-wildcard-role
  namespace: exemption-test
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
EOF

    # Exempted test cases
    log "\nCreating exempted test resources:"
    cat <<EOF | kubectl apply -f - 2>&1 | tee -a "$LOG_FILE"
apiVersion: v1
kind: Pod
metadata:
  name: exempted-capability-pod
  namespace: exemption-test
  labels:
    exemption: "true"
spec:
  containers:
  - name: test-container
    image: nginx:latest
    securityContext:
      capabilities:
        add: ["NET_ADMIN"]
---
apiVersion: v1
kind: Pod
metadata:
  name: exempted-image-pod
  namespace: exemption-test
  labels:
    exemption: "true"
spec:
  containers:
  - name: test-container
    image: docker.io/nginx:latest
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: exempted-wildcard-role
  namespace: exemption-test
  labels:
    exemption: "true"
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
EOF

    # Wait for Gatekeeper to evaluate
    log "\nWaiting for Gatekeeper evaluation..."
    sleep 10
}

verify_exemptions() {
    log "\n${YELLOW}Verifying exemptions...${NC}"

    # Check constraint violations
    log "\n${GREEN}Checking constraint violations:${NC}"
    log_cmd "kubectl get constraints -n gatekeeper-system -o custom-columns=NAME:.metadata.name,VIOLATIONS:.status.totalViolations,ENFORCEMENT:.spec.enforcementAction"

    # Check test resources
    log "\n${GREEN}Checking test resources:${NC}"
    log "\nPods in exemption-test namespace:"
    log_cmd "kubectl get pods -n exemption-test -o wide"
    
    log "\nRoles in exemption-test namespace:"
    log_cmd "kubectl get roles -n exemption-test"

    # Check specific violations
    log "\n${GREEN}Checking specific violations:${NC}"
    
    # Check non-exempted resources
    log "\nNon-exempted resources violations:"
    for resource in capability-test-pod image-test-pod privilege-test-pod test-wildcard-role; do
        log "\nViolations for $resource:"
        log_cmd "kubectl describe $resource -n exemption-test | grep -A 5 'Events:'"
    done

    # Check exempted resources
    log "\nExempted resources violations:"
    for resource in exempted-capability-pod exempted-image-pod exempted-wildcard-role; do
        log "\nViolations for $resource:"
        log_cmd "kubectl describe $resource -n exemption-test | grep -A 5 'Events:'"
    done

    # Check constraint audit results
    log "\nConstraint audit results:"
    for constraint in $(kubectl get constraints -n gatekeeper-system -o name); do
        log "\nAudit for $constraint:"
        log_cmd "kubectl get $constraint -n gatekeeper-system -o jsonpath='{.status.violations}'"
    done
}

cleanup() {
    log "${YELLOW}Cleaning up test resources...${NC}"
    log_cmd "kubectl delete namespace exemption-test --ignore-not-found"
}

main() {
    log "${GREEN}Starting exemption tests...${NC}"
    
    # Cleanup any previous test resources
    cleanup
    
    # Create test cases
    create_test_cases
    
    # Verify exemptions
    verify_exemptions
    
    log "${GREEN}Tests completed. Results saved to: $LOG_FILE${NC}"
}

main