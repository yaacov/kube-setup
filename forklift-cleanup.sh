#!/bin/bash
# forklift-cleanup.sh - Remove Forklift operator from a Kubernetes/OpenShift cluster
#
# This script removes the Forklift installation in the correct order:
# 1. Delete ForkliftController instance (and wait for cleanup)
# 2. Delete the Forklift operator subscription and CSV
# 3. Delete the namespace
#
# Usage: ./forklift-cleanup.sh [--force]

set -e

FORCE=0
NAMESPACE="konveyor-forklift"

for arg in "$@"; do
    case "$arg" in
        --force|-f)
            FORCE=1
            ;;
        --help|-h)
            echo "Usage: $0 [--force]"
            echo ""
            echo "Removes Forklift operator from a Kubernetes or OpenShift cluster."
            echo ""
            echo "Flags:"
            echo "  --force, -f  Skip confirmation prompt"
            echo "  --help, -h   Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check for required tools
if ! command -v kubectl >/dev/null 2>&1; then
    echo "Error: kubectl not found"
    exit 1
fi

echo "=========================================="
echo "Forklift Cleanup"
echo "=========================================="
echo ""
echo "This will remove Forklift from namespace: $NAMESPACE"
echo ""

# Confirmation prompt
if [ "$FORCE" = "0" ]; then
    read -p "Are you sure you want to continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    echo ""
fi

# Step 1: Delete ForkliftController instance
echo "Step 1: Deleting ForkliftController instance..."
if kubectl get forkliftcontroller -n "$NAMESPACE" forklift-controller >/dev/null 2>&1; then
    kubectl delete forkliftcontroller -n "$NAMESPACE" forklift-controller --timeout=120s || true
    echo "  ForkliftController deleted."
else
    echo "  No ForkliftController found, skipping."
fi
echo ""

# Wait for controller pods to terminate
echo "Waiting for controller pods to terminate..."
while kubectl get pods -n "$NAMESPACE" -l app=forklift 2>/dev/null | grep -q forklift; do
    echo "  Waiting for forklift pods to terminate..."
    sleep 5
done
echo "  Controller pods terminated."
echo ""

# Step 2: Delete the Forklift operator subscription
echo "Step 2: Deleting Forklift operator subscription..."
if kubectl get subscription -n "$NAMESPACE" forklift-operator >/dev/null 2>&1; then
    kubectl delete subscription -n "$NAMESPACE" forklift-operator --timeout=60s || true
    echo "  Subscription deleted."
else
    echo "  No subscription found, skipping."
fi
echo ""

# Step 3: Delete the ClusterServiceVersion (CSV)
echo "Step 3: Deleting Forklift ClusterServiceVersion..."
CSV_NAME=$(kubectl get csv -n "$NAMESPACE" -o name 2>/dev/null | grep forklift || true)
if [ -n "$CSV_NAME" ]; then
    kubectl delete "$CSV_NAME" -n "$NAMESPACE" --timeout=60s || true
    echo "  CSV deleted."
else
    echo "  No CSV found, skipping."
fi
echo ""

# Step 4: Delete the CatalogSource
echo "Step 4: Deleting Forklift CatalogSource..."
if kubectl get catalogsource -n "$NAMESPACE" forklift >/dev/null 2>&1; then
    kubectl delete catalogsource -n "$NAMESPACE" forklift --timeout=60s || true
    echo "  CatalogSource deleted."
else
    echo "  No CatalogSource found, skipping."
fi
echo ""

# Step 5: Delete the OperatorGroup
echo "Step 5: Deleting OperatorGroup..."
if kubectl get operatorgroup -n "$NAMESPACE" forklift >/dev/null 2>&1; then
    kubectl delete operatorgroup -n "$NAMESPACE" forklift --timeout=60s || true
    echo "  OperatorGroup deleted."
else
    echo "  No OperatorGroup found, skipping."
fi
echo ""

# Step 6: Delete Forklift CRDs
echo "Step 6: Deleting Forklift CRDs..."
FORKLIFT_CRDS=$(kubectl get crd -o name 2>/dev/null | grep -E "forklift|konveyor" || true)
if [ -n "$FORKLIFT_CRDS" ]; then
    for crd in $FORKLIFT_CRDS; do
        echo "  Deleting $crd..."
        kubectl delete "$crd" --timeout=60s || true
    done
    echo "  CRDs deleted."
else
    echo "  No Forklift CRDs found, skipping."
fi
echo ""

# Step 7: Delete the namespace
echo "Step 7: Deleting namespace $NAMESPACE..."
if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    kubectl delete namespace "$NAMESPACE" --timeout=120s || true
    echo "  Namespace deleted."
else
    echo "  Namespace not found, skipping."
fi
echo ""

echo "=========================================="
echo "Forklift cleanup complete!"
echo "=========================================="
echo ""
