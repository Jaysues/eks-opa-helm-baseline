#!/usr/bin/env python3

import yaml
import sys
import os
from typing import Dict, List, Any

def load_yaml_file(file_path: str) -> dict:
    """Load and parse a YAML file."""
    try:
        # Get absolute path
        abs_path = os.path.abspath(file_path)
        if not os.path.exists(abs_path):
            print(f"File not found: {abs_path}")
            sys.exit(1)
            
        with open(abs_path, 'r') as f:
            return yaml.safe_load(f)
    except yaml.YAMLError as e:
        print(f"Error parsing YAML file {abs_path}: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error reading file {abs_path}: {e}")
        sys.exit(1)

def validate_constraint_structure(values: dict, file_name: str) -> List[str]:
    """Validate the basic structure of constraint values."""
    errors = []
    
    if 'constraints' not in values:
        errors.append(f"[{file_name}] Missing top-level 'constraints' key")
        return errors

    # Check enforcement action
    if 'enforcementAction' not in values['constraints']:
        errors.append(f"[{file_name}] Missing 'enforcementAction' in constraints")

    return errors

def validate_exemptions_structure(constraint: dict, name: str, file_name: str) -> List[str]:
    """Validate the structure of exemptions in a constraint."""
    errors = []
    
    if 'exemptions' not in constraint:
        errors.append(f"[{file_name}] Missing 'exemptions' in {name}")
        return errors

    exemptions = constraint['exemptions']
    
    # Check common exemption fields
    if 'labelSelector' not in exemptions:
        errors.append(f"[{file_name}] Missing 'labelSelector' in {name} exemptions")
    elif not isinstance(exemptions['labelSelector'], dict):
        errors.append(f"[{file_name}] Invalid 'labelSelector' type in {name}")

    return errors

def validate_values_merge(baseline: dict, environment: dict, customer: dict) -> List[str]:
    """Validate that values files can be properly merged."""
    errors = []
    
    # Check that enforcement actions don't conflict
    env_action = environment.get('constraints', {}).get('enforcementAction')
    if env_action and env_action not in ['dryrun', 'deny']:
        errors.append("[environment/dev/values.yaml] Invalid enforcement action in environment values")

    # Validate that baseline excluded namespaces exist
    if not baseline.get('baselines', {}).get('excludedNamespaces'):
        errors.append("[values.yaml] Missing baseline excluded namespaces")

    return errors

def main():
    # File paths - adjust as needed
    baseline_path = "../values.yaml"
    environment_path = "../environment/dev/values.yaml"
    customer_path = "../customer/customer-1/values.yaml"

    print(f"Validating files:")
    print(f"Baseline: {os.path.abspath(baseline_path)}")
    print(f"Environment: {os.path.abspath(environment_path)}")
    print(f"Customer: {os.path.abspath(customer_path)}")
    print("-------------------")

    # Load YAML files
    baseline = load_yaml_file(baseline_path)
    environment = load_yaml_file(environment_path)
    customer = load_yaml_file(customer_path)

    errors = []

    # Validate basic structure
    errors.extend(validate_constraint_structure(baseline, "values.yaml"))
    errors.extend(validate_constraint_structure(environment, "environment/dev/values.yaml"))
    errors.extend(validate_constraint_structure(customer, "customer/customer-1/values.yaml"))

    # Validate values merge
    errors.extend(validate_values_merge(baseline, environment, customer))

    # Validate each constraint in customer values
    for constraint_name, constraint in customer.get('constraints', {}).items():
        errors.extend(validate_exemptions_structure(constraint, constraint_name, "customer/customer-1/values.yaml"))

    # Check for required fields in customer constraints
    required_fields = ['cisBenchmark', 'title', 'type', 'enforces', 'remediation', 'implementation']
    for constraint_name, constraint in customer.get('constraints', {}).items():
        for field in required_fields:
            if field not in constraint:
                errors.append(f"[customer/customer-1/values.yaml] Missing required field '{field}' in {constraint_name}")

    # Report results
    if errors:
        print("Validation failed with the following errors:")
        for error in errors:
            print(f"- {error}")
        sys.exit(1)
    else:
        print("Validation successful! All files are properly structured.")

if __name__ == "__main__":
    main()