#!/bin/bash
# forklift-install.sh - Install Forklift operator on a Kubernetes/OpenShift cluster
#
# This script installs the Forklift operator from the official kubev2v/forklift repository.
# On vanilla Kubernetes, it also installs OLM (Operator Lifecycle Manager).
# On OpenShift, OLM is already present, so it's skipped automatically.
#
# Usage: ./forklift-install.sh [--k8s] [--ocp] [--no-controller]

set -e

# Parse flags
FORCE_K8S=0
FORCE_OCP=0
NO_CONTROLLER=0

for arg in "$@"; do
    case "$arg" in
        --k8s)
            FORCE_K8S=1
            ;;
        --ocp)
            FORCE_OCP=1
            ;;
        --no-controller)
            NO_CONTROLLER=1
            ;;
        --help|-h)
            echo "Usage: $0 [--k8s] [--ocp] [--no-controller]"
            echo ""
            echo "Installs Forklift operator on a Kubernetes or OpenShift cluster."
            echo "The script auto-detects OpenShift and skips OLM installation."
            echo ""
            echo "Flags:"
            echo "  --k8s            Force Kubernetes mode (install OLM)"
            echo "  --ocp            Force OpenShift mode (skip OLM installation)"
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

echo "=========================================="
echo "Forklift Operator Installation"
echo "=========================================="
echo ""

if [ "$IS_OPENSHIFT" = "1" ]; then
    echo "Cluster type: OpenShift (OLM pre-installed)"
else
    echo "Cluster type: Kubernetes"
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

# Install Forklift operator from kubev2v/forklift repository
echo "Installing Forklift operator..."
FORKLIFT_YAML_URL="https://raw.githubusercontent.com/kubev2v/forklift/main/operator/forklift-k8s.yaml"
echo "  Source: $FORKLIFT_YAML_URL"
kubectl apply -f "$FORKLIFT_YAML_URL"

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
  controller_image_fqin: quay.io/kubev2v/forklift-controller:latest
  api_image_fqin: quay.io/kubev2v/forklift-api:latest
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
