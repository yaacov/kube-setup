#!/bin/bash
# forklift-install.sh - Install Forklift operator on a Kubernetes/OpenShift cluster
#
# This script installs the Forklift operator from the official kubev2v/forklift repository.
# On vanilla Kubernetes, it also installs OLM (Operator Lifecycle Manager).
# On OpenShift, OLM is already present, so it's skipped automatically.
#
# Architecture support:
# - amd64: Uses official kubev2v index (default on x86_64)
# - arm64: Uses yaacov/forklift-operator-index:devel-arm64 (default on ARM)
#
# Usage: ./forklift-install.sh [--k8s] [--ocp] [--arm64] [--amd64] [--no-controller]

set -e

# Parse flags
FORCE_K8S=0
FORCE_OCP=0
FORCE_ARM64=0
FORCE_AMD64=0
NO_CONTROLLER=0

for arg in "$@"; do
    case "$arg" in
        --k8s)
            FORCE_K8S=1
            ;;
        --ocp)
            FORCE_OCP=1
            ;;
        --arm64)
            FORCE_ARM64=1
            ;;
        --amd64)
            FORCE_AMD64=1
            ;;
        --no-controller)
            NO_CONTROLLER=1
            ;;
        --help|-h)
            echo "Usage: $0 [--k8s] [--ocp] [--arm64] [--amd64] [--no-controller]"
            echo ""
            echo "Installs Forklift operator on a Kubernetes or OpenShift cluster."
            echo "The script auto-detects OpenShift and architecture, skipping OLM on OpenShift."
            echo ""
            echo "Flags:"
            echo "  --k8s            Force Kubernetes mode (install OLM)"
            echo "  --ocp            Force OpenShift mode (skip OLM installation)"
            echo "  --arm64          Force ARM64 architecture (use ARM operator index)"
            echo "  --amd64          Force AMD64 architecture (use official index)"
            echo "  --no-controller  Skip creating the ForkliftController instance"
            echo "  --help, -h       Show this help message"
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

# Detect cluster type (OpenShift vs vanilla Kubernetes)
detect_openshift() {
    # Check if OpenShift API resources exist
    if kubectl api-resources --api-group=config.openshift.io >/dev/null 2>&1; then
        return 0  # OpenShift detected
    fi
    return 1  # Not OpenShift
}

IS_OPENSHIFT=0
if [ "$FORCE_OCP" = "1" ]; then
    IS_OPENSHIFT=1
elif [ "$FORCE_K8S" = "1" ]; then
    IS_OPENSHIFT=0
elif detect_openshift; then
    IS_OPENSHIFT=1
fi

# Detect architecture
detect_architecture() {
    # Try to get architecture from Kubernetes nodes first
    local node_arch
    node_arch=$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.architecture}' 2>/dev/null || true)
    if [ -n "$node_arch" ]; then
        echo "$node_arch"
        return
    fi
    # Fall back to local machine architecture
    local local_arch
    local_arch=$(uname -m)
    case "$local_arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo "amd64"  # Default to amd64
            ;;
    esac
}

IS_ARM64=0
if [ "$FORCE_ARM64" = "1" ]; then
    IS_ARM64=1
elif [ "$FORCE_AMD64" = "1" ]; then
    IS_ARM64=0
else
    DETECTED_ARCH=$(detect_architecture)
    if [ "$DETECTED_ARCH" = "arm64" ]; then
        IS_ARM64=1
    fi
fi

echo "=========================================="
echo "Forklift Operator Installation"
echo "=========================================="
echo ""

if [ "$IS_OPENSHIFT" = "1" ]; then
    echo "Cluster type: OpenShift (OLM pre-installed)"
else
    echo "Cluster type: Kubernetes"
fi

if [ "$IS_ARM64" = "1" ]; then
    echo "Architecture: ARM64 (using yaacov ARM index)"
else
    echo "Architecture: AMD64 (using official kubev2v index)"
fi
echo ""

# Install OLM only on vanilla Kubernetes
if [ "$IS_OPENSHIFT" = "0" ]; then
    echo "Installing Operator Lifecycle Manager (OLM)..."
    kubectl apply -f https://raw.githubusercontent.com/operator-framework/operator-lifecycle-manager/master/deploy/upstream/quickstart/crds.yaml
    kubectl apply -f https://raw.githubusercontent.com/operator-framework/operator-lifecycle-manager/master/deploy/upstream/quickstart/olm.yaml

    echo "Waiting for OLM operator deployment..."
    while ! kubectl get deployment -n olm olm-operator 2>/dev/null; do
        echo "  Waiting for olm-operator deployment to be created..."
        sleep 10
    done
    kubectl wait deployment -n olm olm-operator --for condition=Available=True --timeout=180s
    echo "OLM installed successfully."
    echo ""
else
    echo "Skipping OLM installation (OpenShift has OLM pre-installed)"
    echo ""
fi

# Set operator index image based on architecture
FORKLIFT_INDEX_AMD64="quay.io/kubev2v/forklift-operator-index:latest"
FORKLIFT_INDEX_ARM64="quay.io/yaacov/forklift-operator-index:devel-arm64"

if [ "$IS_ARM64" = "1" ]; then
    FORKLIFT_INDEX_IMAGE="$FORKLIFT_INDEX_ARM64"
else
    FORKLIFT_INDEX_IMAGE="$FORKLIFT_INDEX_AMD64"
fi

# Install Forklift operator
echo "Installing Forklift operator..."
echo "  Index image: $FORKLIFT_INDEX_IMAGE"

# Create namespace, CatalogSource, OperatorGroup, and Subscription
cat << EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: konveyor-forklift
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: konveyor-forklift
  namespace: konveyor-forklift
spec:
  displayName: Forklift Operator
  publisher: Konveyor
  sourceType: grpc
  image: ${FORKLIFT_INDEX_IMAGE}
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: konveyor-forklift
  namespace: konveyor-forklift
spec:
  targetNamespaces:
    - konveyor-forklift
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: forklift-operator
  namespace: konveyor-forklift
spec:
  channel: development
  installPlanApproval: Automatic
  name: forklift-operator
  source: konveyor-forklift
  sourceNamespace: konveyor-forklift
EOF

echo "Waiting for Forklift operator deployment..."
while ! kubectl get deployment -n konveyor-forklift forklift-operator 2>/dev/null; do
    echo "  Waiting for forklift-operator deployment to be created..."
    sleep 10
done
kubectl wait deployment -n konveyor-forklift forklift-operator --for condition=Available=True --timeout=180s
echo "Forklift operator installed successfully."
echo ""

# Create ForkliftController instance if not skipped
if [ "$NO_CONTROLLER" = "0" ]; then
    echo "Creating ForkliftController instance..."
    cat << EOF | kubectl -n konveyor-forklift apply -f -
apiVersion: forklift.konveyor.io/v1beta1
kind: ForkliftController
metadata:
  name: forklift-controller
  namespace: konveyor-forklift
spec:
  # Feature flags
  feature_ui_plugin: "true"
  feature_validation: "true"
  feature_volume_populator: "true"
  feature_auth_required: "true"
  
  # VMware VDDK image (required for VMware migrations)
  # vddk_image: quay.io/kubev2v/vddk:8.0.0
  
  # Logging
  controller_log_level: 3
  
  # Container images (from quay.io/kubev2v/forklift-operator-index:latest)
  #controller_image_fqin: quay.io/kubev2v/forklift-controller:latest
  #api_image_fqin: quay.io/kubev2v/forklift-api:latest
  # validation_image_fqin: quay.io/kubev2v/forklift-validation:latest
  # ui_plugin_image_fqin: quay.io/kubev2v/forklift-console-plugin:latest
  # must_gather_image_fqin: quay.io/kubev2v/forklift-must-gather:latest
  virt_v2v_image_fqin: quay.io/kubev2v/forklift-virt-v2v:latest
  # cli_download_image_fqin: quay.io/kubev2v/forklift-cli-download:latest
  # populator_controller_image_fqin: quay.io/kubev2v/populator-controller:latest
  # populator_ovirt_image_fqin: quay.io/kubev2v/ovirt-populator:latest
  # populator_openstack_image_fqin: quay.io/kubev2v/openstack-populator:latest
  # populator_vsphere_xcopy_volume_image_fqin: quay.io/kubev2v/vsphere-xcopy-volume-populator:latest
  # ova_provider_server_fqin: quay.io/kubev2v/forklift-ova-provider-server:latest
  # ova_proxy_fqin: quay.io/kubev2v/forklift-ova-proxy:latest
  # hyperv_provider_server_fqin: quay.io/kubev2v/forklift-hyperv-provider-server:latest
  
EOF
    echo "ForkliftController created successfully."
    echo ""
else
    echo "Skipping ForkliftController creation (--no-controller flag set)"
    echo ""
fi

echo "=========================================="
echo "Forklift installation complete!"
echo "=========================================="
echo ""
echo "Namespace: konveyor-forklift"
echo ""
echo "To check the status:"
echo "  kubectl get pods -n konveyor-forklift"
echo "  kubectl get forkliftcontroller -n konveyor-forklift"
echo ""
