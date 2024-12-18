#!/usr/bin/env bash
set -euo pipefail

# Paths - adjust as necessary
CHART_DIR="/home/jaysues/helm-opa/eks-opa-policy/eks-opa-policy-constraints"
BASE_VALUES="${CHART_DIR}/values.yaml"
ENV_VALUES="${CHART_DIR}/environment/dev/values.yaml"
CUSTOMER_VALUES_TEST="${CHART_DIR}/customer/customer-1/values_test.yaml"

NAMESPACE="gatekeeper-system"
LOG_FILE="deploy_log.txt"

exec > >(tee -i ${LOG_FILE}) 2>&1

echo "Deploying constraints with test exemptions..."
helm upgrade --install eks-opa-policy-constraint ${CHART_DIR} \
  -f ${BASE_VALUES} \
  -f ${ENV_VALUES} \
  -f ${CUSTOMER_VALUES_TEST} \
  --namespace ${NAMESPACE} \
  --create-namespace

echo "Waiting for constraints to be ready..."
sleep 5

echo "Validating constraints in cluster..."
kubectl get constrainttemplates -A >> ${LOG_FILE}
kubectl get constraints -A >> ${LOG_FILE}
