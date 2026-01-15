#!/bin/sh
# setup-cluster.sh - Setup NFS mount or CI zip file and export OpenShift cluster credentials
# This script must be SOURCED, not executed: source ./setup-cluster.sh [--login] [--cleanup]
#
# Cross-platform: Linux/macOS, bash/zsh
# Supports two modes:
#   1. NFS mount mode: Set NFS_SERVER to mount credentials from NFS share
#   2. CI zip file mode: Set CI_ZIP_FILE to extract credentials from a zip archive

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
_setup_cluster_forklift_cleanup=0
_setup_cluster_forklift_images=""
_setup_cluster_forklift_images_arg=""

_skip_next=0
_arg_index=0
for _arg in "$@"; do
    _arg_index=$((_arg_index + 1))
    if [ "$_skip_next" = "1" ]; then
        _skip_next=0
        continue
    fi
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
        --forklift-cleanup)
            _setup_cluster_forklift_cleanup=1
            ;;
        --forklift-images)
            _setup_cluster_forklift_images="list"
            ;;
        --forklift-images-clear)
            _setup_cluster_forklift_images="clear"
            ;;
        --forklift-images-set)
            _setup_cluster_forklift_images="set"
            # Get next argument as the image
            _next_arg=$(eval "echo \${$((_arg_index + 1))}")
            if [ -n "$_next_arg" ] && [ "${_next_arg#-}" = "$_next_arg" ]; then
                _setup_cluster_forklift_images_arg="$_next_arg"
                _skip_next=1
            fi
            ;;
        --help|-h)
            echo "Usage: source $0 [--login] [--cleanup] [--forklift] [--forklift-cleanup]"
            echo ""
            echo "Environment variables (required):"
            echo "  CLUSTER     - Cluster name"
            echo ""
            echo "Environment variables (optional - for mounting/extracting new sources):"
            echo "  NFS_SERVER  - NFS server address (e.g., server:/path)"
            echo "  CI_ZIP_FILE - Path to CI zip file containing cluster credentials"
            echo "                (zip structure: home/jenkins/cnv-qe.rhood.us/<CLUSTER>/auth/)"
            echo ""
            echo "  Note: Cluster lookup order:"
            echo "        1. NFS mount directory"
            echo "        2. CI zip extracted directory"
            echo "        3. Downloads directory (auto-extracts <cluster>*.zip if found)"
            echo ""
            echo "Environment variables (optional):"
            echo "  MOUNT_DIR       - NFS mount point directory (default: ~/cluster-credentials)"
            echo "  CI_EXTRACT_DIR  - CI zip extraction directory (default: ~/ci-credentials)"
            echo "  DOWNLOADS_DIR   - Directory to search for cluster zip files (default: ~/Downloads)"
            echo ""
            echo "Flags:"
            echo "  --login                     Also export KUBECONFIG to login to the cluster"
            echo "  --cleanup                   Unset all variables and unmount NFS / remove extracted files"
            echo "  --forklift                  Install Forklift operator"
            echo "  --forklift-cleanup          Remove Forklift operator"
            echo "  --forklift-images           List ForkliftController FQIN images"
            echo "  --forklift-images-set IMG   Set a specific FQIN image"
            echo "  --forklift-images-clear     Clear all FQIN images"
            echo "  --help, -h                  Show this help message"
            return 0 2>/dev/null || exit 0
            ;;
    esac
done
unset _skip_next _arg_index _next_arg

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
    unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _arg
    unset _setup_cluster_forklift_images _setup_cluster_forklift_images_arg
    unset _script_dir _forklift_script _forklift_exit
    return 0 2>/dev/null || exit 0
fi

# Forklift cleanup flow (assumes already logged in, no env vars set/unset)
if [ "$_setup_cluster_forklift_cleanup" = "1" ]; then
    _forklift_cleanup_script="$_script_dir/forklift-cleanup.sh"
    if [ -f "$_forklift_cleanup_script" ]; then
        echo "Running Forklift cleanup..."
        "$_forklift_cleanup_script" --force
        _forklift_cleanup_exit=$?
    else
        echo "Error: forklift-cleanup.sh not found at $_forklift_cleanup_script"
        _forklift_cleanup_exit=1
    fi
    # Cleanup only the temporary variables we created
    unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _arg
    unset _setup_cluster_forklift_images _setup_cluster_forklift_images_arg
    unset _script_dir _forklift_cleanup_script _forklift_cleanup_exit
    return 0 2>/dev/null || exit 0
fi

# Forklift images flow (assumes already logged in, no env vars set/unset)
if [ -n "$_setup_cluster_forklift_images" ]; then
    _forklift_images_script="$_script_dir/forklift-images.sh"
    if [ -f "$_forklift_images_script" ]; then
        case "$_setup_cluster_forklift_images" in
            list)
                "$_forklift_images_script" --list
                ;;
            clear)
                "$_forklift_images_script" --clear
                ;;
            set)
                if [ -z "$_setup_cluster_forklift_images_arg" ]; then
                    echo "Error: --forklift-images-set requires an image argument"
                    echo "Usage: kube-setup --forklift-images-set <image>"
                else
                    "$_forklift_images_script" --set "$_setup_cluster_forklift_images_arg"
                fi
                ;;
        esac
        _forklift_images_exit=$?
    else
        echo "Error: forklift-images.sh not found at $_forklift_images_script"
        _forklift_images_exit=1
    fi
    # Cleanup only the temporary variables we created
    unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _arg
    unset _setup_cluster_forklift_images _setup_cluster_forklift_images_arg
    unset _script_dir _forklift_images_script _forklift_images_exit
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
    
    # Cleanup NFS mount (always try)
    if [ -z "$MOUNT_DIR" ]; then
        MOUNT_DIR="$HOME/cluster-credentials"
    fi
    if mount | grep -q " $MOUNT_DIR "; then
        echo "Unmounting $MOUNT_DIR..."
        sudo umount "$MOUNT_DIR"
        if [ $? -eq 0 ]; then
            echo "Successfully unmounted $MOUNT_DIR"
        else
            echo "Error: Failed to unmount $MOUNT_DIR"
        fi
    fi
    
    # Cleanup CI zip extracted files (always try if directory exists)
    if [ -z "$CI_EXTRACT_DIR" ]; then
        CI_EXTRACT_DIR="$HOME/ci-credentials"
    fi
    if [ -d "$CI_EXTRACT_DIR" ]; then
        echo "Removing extracted CI files from $CI_EXTRACT_DIR..."
        rm -rf "$CI_EXTRACT_DIR"
        if [ $? -eq 0 ]; then
            echo "Successfully removed extracted files"
        else
            echo "Error: Failed to remove extracted files"
        fi
    fi
    
    # Cleanup temporary variables
    unset _setup_cluster_login
    unset _setup_cluster_cleanup
    unset _setup_cluster_forklift
    unset _setup_cluster_forklift_cleanup
    unset _setup_cluster_forklift_images
    unset _setup_cluster_forklift_images_arg
    unset _arg
    unset _script_dir
    
    echo "Cleanup complete."
    return 0 2>/dev/null || exit 0
fi

# Normal setup flow - validate required variables
if [ -z "$CLUSTER" ]; then
    echo "Error: CLUSTER environment variable is not set"
    echo "Usage: export CLUSTER=<cluster-name> && source $0"
    unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _setup_cluster_forklift_images _setup_cluster_forklift_images_arg _arg _script_dir
    return 1 2>/dev/null || exit 1
fi

# Set default MOUNT_DIR if not set
if [ -z "$MOUNT_DIR" ]; then
    MOUNT_DIR="$HOME/cluster-credentials"
fi

# Mount NFS if NFS_SERVER is set
if [ -n "$NFS_SERVER" ]; then
    echo "Setting up NFS mount..."
    
    # Ensure mount directory exists
    if [ ! -d "$MOUNT_DIR" ]; then
        echo "Creating mount directory: $MOUNT_DIR"
        mkdir -p "$MOUNT_DIR"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to create mount directory $MOUNT_DIR"
            unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _setup_cluster_forklift_images _setup_cluster_forklift_images_arg _arg _script_dir
            return 1 2>/dev/null || exit 1
        fi
    fi
    
    # Check if NFS is mounted, mount if not
    if ! mount | grep -q " $MOUNT_DIR "; then
        echo "Mounting NFS share $NFS_SERVER to $MOUNT_DIR..."
        sudo mount -t nfs "$NFS_SERVER" "$MOUNT_DIR"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to mount NFS share"
            unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _setup_cluster_forklift_images _setup_cluster_forklift_images_arg _arg _script_dir
            return 1 2>/dev/null || exit 1
        fi
        echo "NFS mounted successfully."
    else
        echo "NFS already mounted at $MOUNT_DIR"
    fi
fi

# Set NFS cluster dir path (may exist from previous mount)
_nfs_cluster_dir="$MOUNT_DIR/$CLUSTER"

# Set default CI_EXTRACT_DIR if not set
if [ -z "$CI_EXTRACT_DIR" ]; then
    CI_EXTRACT_DIR="$HOME/ci-credentials"
fi

# Set default DOWNLOADS_DIR if not set
if [ -z "$DOWNLOADS_DIR" ]; then
    DOWNLOADS_DIR="$HOME/Downloads"
fi

# Extract CI zip file if CI_ZIP_FILE is set
if [ -n "$CI_ZIP_FILE" ]; then
    echo "Setting up CI zip file..."
    
    # Verify zip file exists (warn and continue if not found - Downloads fallback may work)
    if [ ! -f "$CI_ZIP_FILE" ]; then
        echo "Warning: CI zip file not found: $CI_ZIP_FILE (will try Downloads fallback)"
    else
        # Verify unzip is available
        if ! command -v unzip >/dev/null 2>&1; then
            echo "Error: unzip command not found"
            unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _setup_cluster_forklift_images _setup_cluster_forklift_images_arg _arg _script_dir _nfs_cluster_dir
            return 1 2>/dev/null || exit 1
        fi
        
        # Remove old extracted data and create fresh extraction directory
        if [ -d "$CI_EXTRACT_DIR" ]; then
            echo "Removing old extracted data from $CI_EXTRACT_DIR..."
            rm -rf "$CI_EXTRACT_DIR"
        fi
        echo "Creating extraction directory: $CI_EXTRACT_DIR"
        mkdir -p "$CI_EXTRACT_DIR"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to create extraction directory $CI_EXTRACT_DIR"
            unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _setup_cluster_forklift_images _setup_cluster_forklift_images_arg _arg _script_dir _nfs_cluster_dir
            return 1 2>/dev/null || exit 1
        fi
        
        # Extract the zip file
        echo "Extracting CI zip file to $CI_EXTRACT_DIR..."
        unzip -o -q "$CI_ZIP_FILE" -d "$CI_EXTRACT_DIR"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to extract CI zip file"
            unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _setup_cluster_forklift_images _setup_cluster_forklift_images_arg _arg _script_dir _nfs_cluster_dir
            return 1 2>/dev/null || exit 1
        fi
        echo "CI zip file extracted successfully."
    fi
fi

# Set zip cluster dir path (may exist from previous extraction)
# Expected structure: home/jenkins/cnv-qe.rhood.us/<CLUSTER>/auth/
_zip_cluster_dir="$CI_EXTRACT_DIR/home/jenkins/cnv-qe.rhood.us/$CLUSTER"

# Find cluster directory: try NFS first, then ZIP, then Downloads
_cluster_dir=""
if [ -n "$_nfs_cluster_dir" ] && [ -d "$_nfs_cluster_dir" ]; then
    echo "Found cluster in NFS: $_nfs_cluster_dir"
    _cluster_dir="$_nfs_cluster_dir"
elif [ -n "$_zip_cluster_dir" ] && [ -d "$_zip_cluster_dir" ]; then
    echo "Found cluster in CI zip: $_zip_cluster_dir"
    _cluster_dir="$_zip_cluster_dir"
else
    # Try to find and extract zip file from Downloads directory
    if [ -d "$DOWNLOADS_DIR" ]; then
        # Look for zip file matching <cluster-name>*.zip pattern (case-insensitive)
        _found_zip=$(find "$DOWNLOADS_DIR" -maxdepth 1 -type f -iname "$CLUSTER*.zip" 2>/dev/null | head -1)
        
        if [ -n "$_found_zip" ]; then
            echo "Found cluster zip in Downloads: $_found_zip"
            
            # Verify unzip is available
            if ! command -v unzip >/dev/null 2>&1; then
                echo "Error: unzip command not found"
                unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _setup_cluster_forklift_images _setup_cluster_forklift_images_arg _arg _script_dir _nfs_cluster_dir _zip_cluster_dir _found_zip
                return 1 2>/dev/null || exit 1
            fi
            
            # Remove old extracted data and create fresh extraction directory
            if [ -d "$CI_EXTRACT_DIR" ]; then
                echo "Removing old extracted data from $CI_EXTRACT_DIR..."
                rm -rf "$CI_EXTRACT_DIR"
            fi
            echo "Creating extraction directory: $CI_EXTRACT_DIR"
            mkdir -p "$CI_EXTRACT_DIR"
            if [ $? -ne 0 ]; then
                echo "Error: Failed to create extraction directory $CI_EXTRACT_DIR"
                unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _setup_cluster_forklift_images _setup_cluster_forklift_images_arg _arg _script_dir _nfs_cluster_dir _zip_cluster_dir _found_zip
                return 1 2>/dev/null || exit 1
            fi
            
            # Extract the zip file
            echo "Extracting zip file to $CI_EXTRACT_DIR..."
            unzip -o -q "$_found_zip" -d "$CI_EXTRACT_DIR"
            if [ $? -ne 0 ]; then
                echo "Error: Failed to extract zip file"
                unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _setup_cluster_forklift_images _setup_cluster_forklift_images_arg _arg _script_dir _nfs_cluster_dir _zip_cluster_dir _found_zip
                return 1 2>/dev/null || exit 1
            fi
            echo "Zip file extracted successfully."
            
            # Re-check the zip cluster directory
            if [ -d "$_zip_cluster_dir" ]; then
                echo "Found cluster in extracted zip: $_zip_cluster_dir"
                _cluster_dir="$_zip_cluster_dir"
            fi
        fi
        unset _found_zip
    fi
fi

# Verify cluster directory was found
if [ -z "$_cluster_dir" ]; then
    echo "Error: Cluster '$CLUSTER' not found in any configured source"
    if [ -d "$MOUNT_DIR" ] && [ -n "$(ls -A "$MOUNT_DIR" 2>/dev/null)" ]; then
        echo "  Checked NFS: $_nfs_cluster_dir"
        echo "  Available clusters in NFS:"
        ls "$MOUNT_DIR" 2>/dev/null | head -20 | sed 's/^/    /'
    fi
    if [ -d "$CI_EXTRACT_DIR/home/jenkins/cnv-qe.rhood.us" ]; then
        echo "  Checked CI zip: $_zip_cluster_dir"
        echo "  Available clusters in CI zip:"
        ls "$CI_EXTRACT_DIR/home/jenkins/cnv-qe.rhood.us" 2>/dev/null | head -20 | sed 's/^/    /'
    fi
    if [ -d "$DOWNLOADS_DIR" ]; then
        echo "  Checked Downloads: $DOWNLOADS_DIR/$CLUSTER*.zip (not found)"
    fi
    unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _arg _cluster_dir _nfs_cluster_dir _zip_cluster_dir _script_dir
    return 1 2>/dev/null || exit 1
fi
unset _nfs_cluster_dir _zip_cluster_dir

# Verify auth directory exists
_auth_dir="$_cluster_dir/auth"
if [ ! -d "$_auth_dir" ]; then
    echo "Error: Auth directory not found: $_auth_dir"
    unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _arg _cluster_dir _auth_dir _nfs_cluster_dir _zip_cluster_dir _script_dir
    return 1 2>/dev/null || exit 1
fi

# Verify required files exist
_kubeconfig_file="$_auth_dir/kubeconfig"
_password_file="$_auth_dir/kubeadmin-password"

if [ ! -f "$_kubeconfig_file" ]; then
    echo "Error: kubeconfig file not found: $_kubeconfig_file"
    unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _arg _cluster_dir _auth_dir _kubeconfig_file _password_file _script_dir
    return 1 2>/dev/null || exit 1
fi

if [ ! -f "$_password_file" ]; then
    echo "Error: kubeadmin-password file not found: $_password_file"
    unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _arg _cluster_dir _auth_dir _kubeconfig_file _password_file _script_dir
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
        unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _arg _cluster_dir _auth_dir _kubeconfig_file _password_file _script_dir
        return 1 2>/dev/null || exit 1
    fi
    
    # Use default SA in openshift-cluster-version namespace (has cluster-admin)
    echo "Getting token for SA default in openshift-cluster-version..."
    _token_value=$(KUBECONFIG="$_kubeconfig_file" kubectl create token default -n openshift-cluster-version 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$_token_value" ]; then
        echo "Error: Could not obtain SA token"
        echo "  $_token_value"
        echo "  Note: Requires kubectl 1.24+"
        unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _arg _cluster_dir _auth_dir _kubeconfig_file _password_file _token_value _script_dir
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
unset _setup_cluster_login _setup_cluster_cleanup _setup_cluster_forklift _setup_cluster_forklift_cleanup _arg
unset _setup_cluster_forklift_images _setup_cluster_forklift_images_arg
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
