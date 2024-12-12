#!/bin/bash

# Script to clean all ConstraintTemplates and Constraints in a Gatekeeper deployment
# Ensure kubectl is configured to point to your k3s cluster

echo "Cleaning up Gatekeeper ConstraintTemplates and Constraints..."

# Step 1: Delete all Constraints
echo "Finding and deleting all Constraints..."
constraints=$(kubectl get constraints --no-headers -o custom-columns=":metadata.name,:kind" 2>/dev/null)

if [[ -n "$constraints" ]]; then
    while read -r constraint_name constraint_kind; do
        echo "Deleting Constraint: $constraint_kind/$constraint_name"
        kubectl delete "$constraint_kind" "$constraint_name" --ignore-not-found=true
    done <<< "$constraints"
else
    echo "No Constraints found."
fi

# Step 2: Delete all ConstraintTemplates
echo "Finding and deleting all ConstraintTemplates..."
templates=$(kubectl get constrainttemplates --no-headers -o custom-columns=":metadata.name" 2>/dev/null)

if [[ -n "$templates" ]]; then
    for template in $templates; do
        echo "Deleting ConstraintTemplate: $template"
        kubectl delete constrainttemplate "$template" --ignore-not-found=true
    done
else
    echo "No ConstraintTemplates found."
fi

echo "Gatekeeper cleanup completed successfully."
