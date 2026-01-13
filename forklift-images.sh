#!/bin/bash
# forklift-images.sh - Manage ForkliftController FQIN images
#
# This script lists, clears, or sets FQIN (Fully Qualified Image Name) images
# in the ForkliftController spec.
#
# Usage:
#   ./forklift-images.sh                    # List current FQIN images
#   ./forklift-images.sh --list             # List current FQIN images
#   ./forklift-images.sh --clear            # Clear all FQIN images
#   ./forklift-images.sh --set <image>      # Set an image based on its name

set -e

NAMESPACE="${NAMESPACE:-konveyor-forklift}"
CONTROLLER_NAME="${CONTROLLER_NAME:-forklift-controller}"

# All known FQIN fields - format: "image_name:fqin_field"
FQIN_MAPPINGS="
forklift-controller:controller_image_fqin
forklift-api:api_image_fqin
forklift-validation:validation_image_fqin
forklift-console-plugin:ui_plugin_image_fqin
forklift-must-gather:must_gather_image_fqin
forklift-virt-v2v:virt_v2v_image_fqin
forklift-cli-download:cli_download_image_fqin
populator-controller:populator_controller_image_fqin
ovirt-populator:populator_ovirt_image_fqin
openstack-populator:populator_openstack_image_fqin
vsphere-xcopy-volume-populator:populator_vsphere_xcopy_volume_image_fqin
forklift-ova-provider-server:ova_provider_server_fqin
forklift-ova-proxy:ova_proxy_fqin
forklift-hyperv-provider-server:hyperv_provider_server_fqin
"

# All FQIN field names for iteration
ALL_FQIN_FIELDS="
controller_image_fqin
api_image_fqin
validation_image_fqin
ui_plugin_image_fqin
must_gather_image_fqin
virt_v2v_image_fqin
cli_download_image_fqin
populator_controller_image_fqin
populator_ovirt_image_fqin
populator_openstack_image_fqin
populator_vsphere_xcopy_volume_image_fqin
ova_provider_server_fqin
ova_proxy_fqin
hyperv_provider_server_fqin
"

# Get FQIN field name from image name
get_fqin_field() {
    local image_name="$1"
    echo "$FQIN_MAPPINGS" | grep "^${image_name}:" | cut -d: -f2
}

# Get image name from FQIN field
get_image_name() {
    local fqin_field="$1"
    echo "$FQIN_MAPPINGS" | grep ":${fqin_field}$" | cut -d: -f1
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Manage ForkliftController FQIN (Fully Qualified Image Name) images.

Options:
  --list              List current FQIN images (default action)
  --clear             Clear all FQIN images from the controller spec
  --set <image>       Set an image based on its name
                      Example: --set quay.io/kubev2v/forklift-controller:latest
  --help, -h          Show this help message

Environment Variables:
  NAMESPACE           Namespace containing ForkliftController (default: konveyor-forklift)
  CONTROLLER_NAME     Name of the ForkliftController (default: forklift-controller)

Supported Image Names:
EOF
    echo "$FQIN_MAPPINGS" | grep -v '^$' | while read -r line; do
        name=$(echo "$line" | cut -d: -f1)
        field=$(echo "$line" | cut -d: -f2)
        printf "  %-40s -> %s\n" "$name" "$field"
    done | sort
    echo ""
}

# Check for required tools
check_prerequisites() {
    if ! command -v kubectl >/dev/null 2>&1; then
        echo "Error: kubectl not found"
        exit 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq not found (required for JSON parsing)"
        exit 1
    fi
}

# Get the ForkliftController JSON
get_controller() {
    kubectl get forkliftcontroller "$CONTROLLER_NAME" -n "$NAMESPACE" -o json 2>/dev/null
}

# List current FQIN images
list_images() {
    echo "ForkliftController FQIN Images"
    echo "==============================="
    echo "Namespace: $NAMESPACE"
    echo "Controller: $CONTROLLER_NAME"
    echo ""
    
    local controller_json
    controller_json=$(get_controller)
    
    if [ -z "$controller_json" ]; then
        echo "Error: ForkliftController '$CONTROLLER_NAME' not found in namespace '$NAMESPACE'"
        exit 1
    fi
    
    echo "Currently set FQIN images:"
    echo ""
    
    local found=0
    for field in $ALL_FQIN_FIELDS; do
        [ -z "$field" ] && continue
        value=$(printf '%s' "$controller_json" | jq -r ".spec.$field // empty")
        if [ -n "$value" ]; then
            printf "  %-45s = %s\n" "$field" "$value"
            found=1
        fi
    done
    
    if [ "$found" = "0" ]; then
        echo "  (no FQIN images are currently set)"
    fi
    echo ""
}

# Clear all FQIN images
clear_images() {
    echo "Clearing all FQIN images from ForkliftController..."
    echo "Namespace: $NAMESPACE"
    echo "Controller: $CONTROLLER_NAME"
    echo ""
    
    local controller_json
    controller_json=$(get_controller)
    
    if [ -z "$controller_json" ]; then
        echo "Error: ForkliftController '$CONTROLLER_NAME' not found in namespace '$NAMESPACE'"
        exit 1
    fi
    
    # Build patch to remove all FQIN fields
    local patch_ops=""
    local first=1
    
    for field in $ALL_FQIN_FIELDS; do
        [ -z "$field" ] && continue
        value=$(printf '%s' "$controller_json" | jq -r ".spec.$field // empty")
        
        if [ -n "$value" ]; then
            if [ "$first" = "1" ]; then
                first=0
            else
                patch_ops="${patch_ops},"
            fi
            patch_ops="${patch_ops}{\"op\":\"remove\",\"path\":\"/spec/$field\"}"
            echo "  Removing: $field"
        fi
    done
    
    if [ -z "$patch_ops" ]; then
        echo "  No FQIN images to clear."
        return
    fi
    
    patch_ops="[$patch_ops]"
    
    echo ""
    kubectl patch forkliftcontroller "$CONTROLLER_NAME" -n "$NAMESPACE" \
        --type=json \
        -p "$patch_ops"
    
    echo ""
    echo "All FQIN images cleared successfully."
}

# Set an image based on its name
set_image() {
    local image="$1"
    
    if [ -z "$image" ]; then
        echo "Error: No image specified"
        echo "Usage: $0 --set <image>"
        exit 1
    fi
    
    echo "Setting FQIN image..."
    echo "Namespace: $NAMESPACE"
    echo "Controller: $CONTROLLER_NAME"
    echo "Image: $image"
    echo ""
    
    # Extract image name from the full image path
    # e.g., quay.io/kubev2v/forklift-controller:latest -> forklift-controller
    local image_name
    image_name=$(echo "$image" | sed 's|.*/||' | sed 's|:.*||')
    
    # Find the corresponding FQIN field
    local fqin_field
    fqin_field=$(get_fqin_field "$image_name")
    
    if [ -z "$fqin_field" ]; then
        echo "Error: Unknown image name '$image_name'"
        echo ""
        echo "Supported image names:"
        echo "$FQIN_MAPPINGS" | grep -v '^$' | cut -d: -f1 | sort | sed 's/^/  /'
        exit 1
    fi
    
    echo "Detected image name: $image_name"
    echo "Setting field: $fqin_field"
    echo ""
    
    # Check if controller exists
    if ! get_controller >/dev/null; then
        echo "Error: ForkliftController '$CONTROLLER_NAME' not found in namespace '$NAMESPACE'"
        exit 1
    fi
    
    # Patch the controller
    kubectl patch forkliftcontroller "$CONTROLLER_NAME" -n "$NAMESPACE" \
        --type=merge \
        -p "{\"spec\":{\"$fqin_field\":\"$image\"}}"
    
    echo ""
    echo "Image set successfully: $fqin_field = $image"
}

# Main entry point
main() {
    check_prerequisites
    
    # Default action is list
    local action="list"
    local image=""
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --list)
                action="list"
                shift
                ;;
            --clear)
                action="clear"
                shift
                ;;
            --set)
                action="set"
                shift
                if [ $# -gt 0 ]; then
                    image="$1"
                    shift
                fi
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    case "$action" in
        list)
            list_images
            ;;
        clear)
            clear_images
            ;;
        set)
            set_image "$image"
            ;;
    esac
}

main "$@"
