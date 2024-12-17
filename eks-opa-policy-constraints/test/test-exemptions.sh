#!/usr/bin/env bash

set -euo pipefail

# Variables
POLICY=${POLICY:-"eksallowedcapabilities"} # Set your policy here or pass as env var: POLICY=eksallowedcapabilities ./test_exemption_logic.sh
CHART_DIR="../" # Adjust if script is placed in test/ directory and chart is up one level
CUSTOMER_VALUES="${CHART_DIR}/customer/customer-1/values.yaml"
ENV_VALUES="${CHART_DIR}/environment/dev/values.yaml"
BASE_VALUES="${CHART_DIR}/values.yaml"
NAMESPACE="exemption-test"
LOG_FILE="test_${POLICY}.log"

# Start logging
exec > >(tee -i ${LOG_FILE}) 2>&1

echo "===== Starting Exemption Logic Test for Policy: ${POLICY} ====="

# Ensure namespace doesn't exist
kubectl delete ns ${NAMESPACE} --ignore-not-found

# A helper function to restore original customer values after test
restore_customer_values() {
  echo "Restoring original customer values..."
  git checkout -- "${CUSTOMER_VALUES}" || true
}
trap restore_customer_values EXIT

# Identify the parameters for the given POLICY by inspecting the constraints YAML in templates or from known structure.
# For simplicity, we assume we know the fields from the given policy.
# We'll add test values to each exemption parameter.

# Example test values (adjust these based on the fields your policy supports):
EXCLUDED_NAMESPACES='["test-exempt-ns"]'
EXCLUDED_CONTAINERS='["test-exempt-container"]'
EXCLUDED_IMAGES='["test-image:*"]'
ALLOWED_CAPABILITIES='["NET_ADMIN"]'
REQUIRED_DROP_CAPABILITIES='["ALL"]'
ALLOWED_REGISTRIES='["test-registry.io"]'
ALLOWED_PULL_POLICIES='["IfNotPresent"]'
ALLOWED_SECRETS='["test-secret"]'
ALLOWED_HOST_PATHS='[{"pathPrefix":"/test/exempt-path","readOnly":true}]'
ALLOWED_ROLES='["system:masters"]'
EXCLUDED_ROLES='["test-role"]'
ALLOWED_RESOURCES='["test-resource"]'
ALLOWED_SYSCTLS='["net.ipv4.ip_local_port_range"]'
ENFORCE_PROBES='["livenessProbe"]'

# Label selector logic for testing matchLabels/matchExpressions:
MATCH_LABELS='{ "exempt-label": "true" }'
MATCH_EXPRESSIONS='[{"key":"env","operator":"In","values":["test"]}]'

echo "Modifying customer values to insert test exemptions for policy: ${POLICY}"

# Use yq to modify the customer values YAML

# General pattern for yq:
# yq eval '(path.to.field) = value' -i file.yaml

yq eval ".constraints.${POLICY}.exemptions.excludedNamespaces = ${EXCLUDED_NAMESPACES}" -i "${CUSTOMER_VALUES}" || true
yq eval ".constraints.${POLICY}.exemptions.excludedContainers = ${EXCLUDED_CONTAINERS}" -i "${CUSTOMER_VALUES}" || true
yq eval ".constraints.${POLICY}.exemptions.excludedImages = ${EXCLUDED_IMAGES}" -i "${CUSTOMER_VALUES}" || true
yq eval ".constraints.${POLICY}.exemptions.allowedCapabilities = ${ALLOWED_CAPABILITIES}" -i "${CUSTOMER_VALUES}" || true
yq eval ".constraints.${POLICY}.exemptions.requiredDropCapabilities = ${REQUIRED_DROP_CAPABILITIES}" -i "${CUSTOMER_VALUES}" || true
yq eval ".constraints.${POLICY}.exemptions.allowedRegistries = ${ALLOWED_REGISTRIES}" -i "${CUSTOMER_VALUES}" || true
yq eval ".constraints.${POLICY}.exemptions.requireDigests = true" -i "${CUSTOMER_VALUES}" || true
yq eval ".constraints.${POLICY}.exemptions.allowedPullPolicies = ${ALLOWED_PULL_POLICIES}" -i "${CUSTOMER_VALUES}" || true
yq eval ".constraints.${POLICY}.exemptions.allowedSecrets = ${ALLOWED_SECRETS}" -i "${CUSTOMER_VALUES}" || true
yq eval ".constraints.${POLICY}.exemptions.allowedHostPaths = ${ALLOWED_HOST_PATHS}" -i "${CUSTOMER_VALUES}" || true
yq eval ".constraints.${POLICY}.exemptions.allowedRoles = ${ALLOWED_ROLES}" -i "${CUSTOMER_VALUES}" || true
yq eval ".constraints.${POLICY}.exemptions.excludedRoles = ${EXCLUDED_ROLES}" -i "${CUSTOMER_VALUES}" || true
yq eval ".constraints.${POLICY}.exemptions.allowedResources = ${ALLOWED_RESOURCES}" -i "${CUSTOMER_VALUES}" || true
yq eval ".constraints.${POLICY}.exemptions.allowedSysctls = ${ALLOWED_SYSCTLS}" -i "${CUSTOMER_VALUES}" || true
yq eval ".constraints.${POLICY}.exemptions.enforceProbes = ${ENFORCE_PROBES}" -i "${CUSTOMER_VALUES}" || true
yq eval ".constraints.${POLICY}.exemptions.labelSelector.matchLabels = ${MATCH_LABELS}" -i "${CUSTOMER_VALUES}" || true
yq eval ".constraints.${POLICY}.exemptions.labelSelector.matchExpressions = ${MATCH_EXPRESSIONS}" -i "${CUSTOMER_VALUES}" || true

echo "Deploying Helm chart with updated customer exemptions..."
helm upgrade --install eks-opa-policy-constraint ${CHART_DIR} \
  -f ${BASE_VALUES} \
  -f ${ENV_VALUES} \
  -f ${CUSTOMER_VALUES} \
  --namespace gatekeeper-system \
  --create-namespace

# Wait for constraints to be applied
echo "Waiting for constraints to be ready..."
sleep 5

echo "Creating test namespace and resources..."
kubectl create namespace ${NAMESPACE}

# Deploy a resource that should PASS due to exemptions
# Matches labelSelector and uses excludedContainers, etc.
echo "Deploying exempted resource..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: exempted-${POLICY}-pod
  namespace: ${NAMESPACE}
  labels:
    exempt-label: "true"
    env: "test"
spec:
  containers:
  - name: test-exempt-container
    image: test-image:latest
    securityContext:
      capabilities:
        add: ["NET_ADMIN"]
        drop: ["ALL"]
EOF

sleep 3
echo "Verifying exempted resource is running..."
if kubectl get pod -n ${NAMESPACE} exempted-${POLICY}-pod | grep Running; then
  echo "SUCCESS: Exempted resource passed as expected."
else
  echo "FAILURE: Exempted resource did not run as expected."
  exit 1
fi

# Deploy a resource that should FAIL even with exemptions
# This resource should not match labelSelector or exemptions
echo "Deploying violating resource..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: violating-${POLICY}-pod
  namespace: ${NAMESPACE}
  labels:
    exempt-label: "false"
    env: "prod"
spec:
  containers:
  - name: non-exempt-container
    image: nonallowedimage:latest
    securityContext:
      capabilities:
        add: ["SYS_ADMIN"] # not allowed if we rely on allowedCapabilities
EOF

sleep 3
echo "Verifying violating resource is NOT running..."
if kubectl get pod -n ${NAMESPACE} violating-${POLICY}-pod 2>&1 | grep "Running"; then
  echo "FAILURE: Violating resource is running when it should not."
  exit 1
else
  echo "SUCCESS: Violating resource was blocked as expected."
fi

echo "Cleaning up test resources..."
kubectl delete ns ${NAMESPACE} --ignore-not-found

echo "All tests for policy ${POLICY} completed successfully."
echo "Logs available in ${LOG_FILE}"
