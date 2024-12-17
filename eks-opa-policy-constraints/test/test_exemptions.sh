#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="exemption-test"
LOG_FILE="test_results.txt"
exec > >(tee -i ${LOG_FILE}) 2>&1

echo "Creating test namespace..."
kubectl create ns ${NAMESPACE} || true

echo "Deploying a resource that should PASS due to exemptions..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: exempted-pod
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
echo "Checking if exempted pod is running..."
if kubectl get pod -n ${NAMESPACE} exempted-pod | grep Running; then
  echo "PASS: Exempted pod is allowed as expected."
else
  echo "FAIL: Exempted pod did not run as expected."
  exit 1
fi

echo "Deploying a resource that should FAIL due to policy (no exemptions match)..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: violating-pod
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
        add: ["SYS_ADMIN"] # not allowed by allowedCapabilities
EOF

sleep 3
echo "Checking if violating pod is blocked..."
if kubectl get pod -n ${NAMESPACE} violating-pod 2>&1 | grep "Running"; then
  echo "FAIL: Violating pod is running when it should not."
  exit 1
else
  echo "PASS: Violating pod was blocked as expected."
fi

echo "All tests completed successfully."

echo "Collecting constraints for final verification..."
kubectl get constraints -A -o yaml >> ${LOG_FILE}

echo "Cleaning up resources..."
kubectl delete ns ${NAMESPACE} --ignore-not-found
