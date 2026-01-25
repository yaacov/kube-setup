#!/bin/bash
# kubevirt-install.sh - Install KubeVirt and CDI on a Kubernetes cluster
#
# This script installs KubeVirt and CDI (Containerized Data Importer) from
# the official kubevirt repositories.
#
# Usage: ./kubevirt-install.sh [--no-cdi] [--version VERSION] [--cdi-version VERSION]

set -e

# Parse flags
NO_CDI=0
KUBEVIRT_VERSION=""
CDI_VERSION=""

while [ $# -gt 0 ]; do
    case "$1" in
        --no-cdi)
            NO_CDI=1
            shift
            ;;
        --version)
            KUBEVIRT_VERSION="$2"
            shift 2
            ;;
        --cdi-version)
            CDI_VERSION="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--no-cdi] [--version VERSION] [--cdi-version VERSION]"
            echo ""
            echo "Installs KubeVirt and CDI on a Kubernetes cluster."
            echo ""
            echo "Flags:"
            echo "  --no-cdi              Skip CDI installation"
            echo "  --version VERSION     Install specific KubeVirt version (default: latest)"
            echo "  --cdi-version VERSION Install specific CDI version (default: latest)"
            echo "  --help, -h            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
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

if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl not found"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq not found"
    exit 1
fi

echo "=========================================="
echo "KubeVirt Installation"
echo "=========================================="
echo ""

# Get KubeVirt version
if [ -z "$KUBEVIRT_VERSION" ]; then
    echo "Fetching latest KubeVirt version..."
    KUBEVIRT_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases/latest | jq -r .tag_name)
    if [ -z "$KUBEVIRT_VERSION" ] || [ "$KUBEVIRT_VERSION" = "null" ]; then
        echo "Error: Failed to fetch latest KubeVirt version"
        exit 1
    fi
fi
echo "KubeVirt version: $KUBEVIRT_VERSION"
echo ""

# Install KubeVirt operator
echo "Installing KubeVirt operator..."
KUBEVIRT_OPERATOR_URL="https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"
echo "  Source: $KUBEVIRT_OPERATOR_URL"
kubectl apply -f "$KUBEVIRT_OPERATOR_URL"

echo "Waiting for KubeVirt operator deployment..."
while ! kubectl get deployment -n kubevirt virt-operator 2>/dev/null; do
    echo "  Waiting for virt-operator deployment to be created..."
    sleep 10
done
kubectl wait deployment -n kubevirt virt-operator --for condition=Available=True --timeout=300s
echo "KubeVirt operator installed successfully."
echo ""

# Install KubeVirt CR
echo "Creating KubeVirt CR..."
KUBEVIRT_CR_URL="https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml"
echo "  Source: $KUBEVIRT_CR_URL"
kubectl apply -f "$KUBEVIRT_CR_URL"

echo "Waiting for KubeVirt to be ready..."
kubectl wait kubevirt -n kubevirt kubevirt --for condition=Available=True --timeout=600s
echo "KubeVirt installed successfully."
echo ""

# Check if cluster nodes have KVM support and enable emulation if not
echo "Checking cluster KVM support..."
# Wait for virt-handler to register device plugin
sleep 10
KVM_AVAILABLE=$(kubectl get nodes -o jsonpath='{.items[0].status.allocatable.devices\.kubevirt\.io/kvm}' 2>/dev/null)
if [ -z "$KVM_AVAILABLE" ] || [ "$KVM_AVAILABLE" = "0" ]; then
    echo "No KVM support detected on cluster nodes - enabling software emulation..."
    kubectl patch kubevirt kubevirt -n kubevirt --type=merge \
        -p '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
    echo "Restarting virt-handler pods..."
    kubectl delete pods -n kubevirt -l kubevirt.io=virt-handler
    echo "Waiting for virt-handler to restart..."
    sleep 30
    echo "Software emulation enabled."
else
    echo "KVM support detected on cluster nodes (kvm devices: $KVM_AVAILABLE)."
fi
echo ""

# Install CDI if not skipped
if [ "$NO_CDI" = "0" ]; then
    echo "=========================================="
    echo "CDI (Containerized Data Importer) Installation"
    echo "=========================================="
    echo ""

    # Get CDI version
    if [ -z "$CDI_VERSION" ]; then
        echo "Fetching latest CDI version..."
        CDI_VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases/latest | jq -r .tag_name)
        if [ -z "$CDI_VERSION" ] || [ "$CDI_VERSION" = "null" ]; then
            echo "Error: Failed to fetch latest CDI version"
            exit 1
        fi
    fi
    echo "CDI version: $CDI_VERSION"
    echo ""

    # Install CDI operator
    echo "Installing CDI operator..."
    CDI_OPERATOR_URL="https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml"
    echo "  Source: $CDI_OPERATOR_URL"
    kubectl apply -f "$CDI_OPERATOR_URL"

    echo "Waiting for CDI operator deployment..."
    while ! kubectl get deployment -n cdi cdi-operator 2>/dev/null; do
        echo "  Waiting for cdi-operator deployment to be created..."
        sleep 10
    done
    kubectl wait deployment -n cdi cdi-operator --for condition=Available=True --timeout=300s
    echo "CDI operator installed successfully."
    echo ""

    # Install CDI CR
    echo "Creating CDI CR..."
    CDI_CR_URL="https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml"
    echo "  Source: $CDI_CR_URL"
    kubectl apply -f "$CDI_CR_URL"

    echo "Waiting for CDI to be ready..."
    kubectl wait cdi -n cdi cdi --for condition=Available=True --timeout=300s
    echo "CDI installed successfully."
    echo ""
else
    echo "Skipping CDI installation (--no-cdi flag set)"
    echo ""
fi

echo "=========================================="
echo "Installation complete!"
echo "=========================================="
echo ""
echo "KubeVirt namespace: kubevirt"
if [ "$NO_CDI" = "0" ]; then
    echo "CDI namespace: cdi"
fi
echo ""
echo "To check the status:"
echo "  kubectl get pods -n kubevirt"
echo "  kubectl get kubevirt -n kubevirt"
if [ "$NO_CDI" = "0" ]; then
    echo "  kubectl get pods -n cdi"
    echo "  kubectl get cdi -n cdi"
fi
echo ""
if [ -z "$KVM_AVAILABLE" ] || [ "$KVM_AVAILABLE" = "0" ]; then
    echo "NOTE: Software emulation was automatically enabled (no KVM on cluster nodes)."
    echo "      VMs will run slower but work without hardware virtualization support."
else
    echo "NOTE: KVM hardware virtualization is available on this cluster."
fi
echo ""
