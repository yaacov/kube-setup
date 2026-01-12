#!/bin/sh
# setup-cluster.sh - Setup NFS mount and export OpenShift cluster credentials
# This script must be SOURCED, not executed: source ./setup-cluster.sh [--login] [--cleanup]
#
# Cross-platform: Linux/macOS, bash/zsh

# Determine script directory (works when sourced from any location)
if [ -n "$BASH_SOURCE" ]; then
    _script_dir="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"
elif [ -n "$ZSH_VERSION" ]; then
    _script_dir="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
    _script_dir="$(cd "$(dirname "$0")" && pwd)"
fi

# Parse flags
_setup_cluster_login=0
_setup_cluster_cleanup=0
_setup_cluster_forklift=0

for _arg in "$@"; do
    case "$_arg" in
        --login)
            _setup_cluster_login=1
            ;;
        --cleanup)
            _setup_cluster_cleanup=1
            ;;
        --forklift)
            _setup_cluster_forklift=1
            ;;
        --help|-h)
            echo "Usage: source $0 [--login] [--cleanup] [--forklift]"
            echo ""
            echo "Environment variables (required for setup):"
            echo "  CLUSTER     - Cluster name"
            echo "  NFS_SERVER  - NFS server address (e.g., server:/path)"
            echo ""
            echo "Environment variables (optional):"
            echo "  MOUNT_DIR   - Mount point directory (default: ~/cluster-credentials)"
            echo ""
            echo "Flags:"
            echo "  --login     - Also export KUBECONFIG to login to the cluster"
            echo "  --cleanup   - Unset all variables and unmount NFS"
            echo "  --forklift  - Install Forklift operator (assumes already logged in)"
            echo "  --help, -h  - Show this help message"
            return 0 2>/dev/null || exit 0
            ;;
    esac
done

# Forklift-only flow (assumes already logged in, no env vars set/unset)
if [ "$_setup_cluster_forklift" = "1" ]; then
    _forklift_script="$_script_dir/forklift-install.sh"
    if [ -f "$_forklift_script" ]; then
        echo "Running Forklift installation..."
        "$_forklift_script"
        _forklift_exit=$?
    else
        echo "Error: forklift-install.sh not found at $_forklift_script"
        _forklift_exit=1
    fi
    # Cleanup only the temporary variables we created
    unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _arg
    unset _script_dir _forklift_script _forklift_exit
    return 0 2>/dev/null || exit 0
fi

# Cleanup flow
if [ "$_setup_cluster_cleanup" = "1" ]; then
    echo "Cleaning up cluster environment..."
    
    # Unset all exported variables
    unset KUBE_USER
    unset KUBE_PASSWORD
    unset KUBE_API_URL
    unset KUBE_UI_URL
    unset KUBE_TOKEN
    unset KUBECONFIG
    
    # Set default MOUNT_DIR if not set
    if [ -z "$MOUNT_DIR" ]; then
        MOUNT_DIR="$HOME/cluster-credentials"
    fi
    
    # Unmount if mounted
    if mount | grep -q " $MOUNT_DIR "; then
        echo "Unmounting $MOUNT_DIR..."
        sudo umount "$MOUNT_DIR"
        if [ $? -eq 0 ]; then
            echo "Successfully unmounted $MOUNT_DIR"
        else
            echo "Error: Failed to unmount $MOUNT_DIR"
        fi
    else
        echo "NFS not mounted at $MOUNT_DIR"
    fi
    
    # Cleanup temporary variables
    unset _setup_cluster_login
    unset _setup_cluster_cleanup
    unset _setup_cluster_forklift
    unset _arg
    unset _script_dir
    
    echo "Cleanup complete."
    return 0 2>/dev/null || exit 0
fi

# Normal setup flow - validate required variables
if [ -z "$CLUSTER" ]; then
    echo "Error: CLUSTER environment variable is not set"
    echo "Usage: export CLUSTER=<cluster-name> && source $0"
    unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _arg _script_dir
    return 1 2>/dev/null || exit 1
fi

if [ -z "$NFS_SERVER" ]; then
    echo "Error: NFS_SERVER environment variable is not set"
    echo "Usage: export NFS_SERVER=<server>:<path> && source $0"
    unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _arg _script_dir
    return 1 2>/dev/null || exit 1
fi

# Set default MOUNT_DIR if not set
if [ -z "$MOUNT_DIR" ]; then
    MOUNT_DIR="$HOME/cluster-credentials"
fi

# Ensure mount directory exists
if [ ! -d "$MOUNT_DIR" ]; then
    echo "Creating mount directory: $MOUNT_DIR"
    mkdir -p "$MOUNT_DIR"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create mount directory $MOUNT_DIR"
        unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _arg _script_dir
        return 1 2>/dev/null || exit 1
    fi
fi

# Check if NFS is mounted, mount if not
if ! mount | grep -q " $MOUNT_DIR "; then
    echo "Mounting NFS share $NFS_SERVER to $MOUNT_DIR..."
    sudo mount -t nfs "$NFS_SERVER" "$MOUNT_DIR"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to mount NFS share"
        unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _arg _script_dir
        return 1 2>/dev/null || exit 1
    fi
    echo "NFS mounted successfully."
else
    echo "NFS already mounted at $MOUNT_DIR"
fi

# Verify cluster directory exists
_cluster_dir="$MOUNT_DIR/$CLUSTER"
if [ ! -d "$_cluster_dir" ]; then
    echo "Error: Cluster directory not found: $_cluster_dir"
    echo "Available clusters:"
    ls "$MOUNT_DIR" 2>/dev/null | head -20
    unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _arg _cluster_dir _script_dir
    return 1 2>/dev/null || exit 1
fi

# Verify auth directory exists
_auth_dir="$_cluster_dir/auth"
if [ ! -d "$_auth_dir" ]; then
    echo "Error: Auth directory not found: $_auth_dir"
    unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _arg _cluster_dir _auth_dir _script_dir
    return 1 2>/dev/null || exit 1
fi

# Verify required files exist
_kubeconfig_file="$_auth_dir/kubeconfig"
_password_file="$_auth_dir/kubeadmin-password"

if [ ! -f "$_kubeconfig_file" ]; then
    echo "Error: kubeconfig file not found: $_kubeconfig_file"
    unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _arg _cluster_dir _auth_dir _kubeconfig_file _password_file _script_dir
    return 1 2>/dev/null || exit 1
fi

if [ ! -f "$_password_file" ]; then
    echo "Error: kubeadmin-password file not found: $_password_file"
    unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _arg _cluster_dir _auth_dir _kubeconfig_file _password_file _script_dir
    return 1 2>/dev/null || exit 1
fi

# Export credentials
export KUBE_USER="kubeadmin"
export KUBE_PASSWORD=$(cat "$_password_file")
export KUBE_API_URL=$(grep "server:" "$_kubeconfig_file" | head -1 | awk '{print $2}')

# Extract token if available (some clusters use certificate auth instead)
_token_value=$(grep "token:" "$_kubeconfig_file" | awk '{print $2}')
if [ -z "$_token_value" ]; then
    # No token in kubeconfig - get one using kubectl create token
    if ! command -v kubectl >/dev/null 2>&1; then
        echo "Error: kubectl not found (requires kubectl 1.24+)"
        unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _arg _cluster_dir _auth_dir _kubeconfig_file _password_file _script_dir
        return 1 2>/dev/null || exit 1
    fi
    
    # Use default SA in openshift-cluster-version namespace (has cluster-admin)
    echo "Getting token for SA default in openshift-cluster-version..."
    _token_value=$(KUBECONFIG="$_kubeconfig_file" kubectl create token default -n openshift-cluster-version 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$_token_value" ]; then
        echo "Error: Could not obtain SA token"
        echo "  $_token_value"
        echo "  Note: Requires kubectl 1.24+"
        unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _arg _cluster_dir _auth_dir _kubeconfig_file _password_file _token_value _script_dir
        return 1 2>/dev/null || exit 1
    fi
    
    echo "Successfully obtained cluster-admin token"
fi

if [ -n "$_token_value" ]; then
    export KUBE_TOKEN="$_token_value"
else
    export KUBE_TOKEN=""
fi

# Derive UI URL from API URL
# Transform: https://api.cluster.domain:6443 -> https://console-openshift-console.apps.cluster.domain
_api_url_no_port=$(echo "$KUBE_API_URL" | sed 's/:6443$//')
export KUBE_UI_URL=$(echo "$_api_url_no_port" | sed 's|https://api\.|https://console-openshift-console.apps.|')

# Export KUBECONFIG if --login flag is set
if [ "$_setup_cluster_login" = "1" ]; then
    export KUBECONFIG="$_kubeconfig_file"
    echo "KUBECONFIG exported - kubectl will use cluster: $CLUSTER"
fi

# Cleanup temporary variables
unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _arg
unset _cluster_dir _auth_dir _kubeconfig_file _password_file _api_url_no_port _token_value
unset _script_dir _forklift_script

# Print summary
echo ""
echo "Cluster credentials loaded for: $CLUSTER"
echo "  KUBE_USER:     $KUBE_USER"
echo "  KUBE_PASSWORD: ********"
echo "  KUBE_API_URL:  $KUBE_API_URL"
echo "  KUBE_UI_URL:   $KUBE_UI_URL"
if [ -n "$KUBE_TOKEN" ]; then
    # Show first 20 chars of token (POSIX-compatible way)
    _token_preview=$(echo "$KUBE_TOKEN" | cut -c1-20)
    echo "  KUBE_TOKEN:    ${_token_preview}..."
    unset _token_preview
else
    echo "  KUBE_TOKEN:    (not available - cluster uses certificate auth)"
fi
if [ -n "$KUBECONFIG" ]; then
    echo "  KUBECONFIG:    $KUBECONFIG"
else
    echo "  KUBECONFIG:    (not set - use --login flag to set)"
fi
echo ""
