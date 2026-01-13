# Kube Setup Scripts

A collection of cross-platform shell scripts for Kubernetes/OpenShift cluster management.

## Scripts

- **`kube-setup.sh`** - Mount NFS-shared OpenShift cluster credentials and export them as environment variables
- **`forklift-install.sh`** - Install Forklift operator on a Kubernetes/OpenShift cluster
- **`forklift-cleanup.sh`** - Remove Forklift operator from a cluster
- **`forklift-images.sh`** - Manage ForkliftController FQIN (container) images

---

# kube-setup.sh

A cross-platform shell script to mount NFS-shared OpenShift cluster credentials and export them as environment variables.

## Overview

This script:

1. Mounts an NFS share containing cluster credentials
2. Exports environment variables for cluster authentication
3. Optionally sets `KUBECONFIG` for kubectl access

## Prerequisites

- NFS client installed on your system
  - **Linux**: `nfs-utils` or `nfs-common` package
  - **macOS**: Built-in NFS support
- `sudo` access for mounting NFS shares
- Access to the NFS server containing cluster credentials
- `kubectl` version **1.24+** (required for automatic token retrieval)

## Installation

### Shell Setup

Add the following to your `~/.bashrc` or `~/.zshrc`:

```bash
# Kube setup configuration
export NFS_SERVER="<nfs-server>:<path>"
export MOUNT_DIR="$HOME/cluster-credentials"

# Kube setup function
kube-setup() {
    source /path/to/kube-setup.sh "$@"
}
```

Then reload your shell:

```bash
source ~/.bashrc  # or source ~/.zshrc
```

## Configuration

### Environment Variables

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `CLUSTER` | Yes | Name of the cluster to connect to | - |
| `NFS_SERVER` | Yes | NFS server address (`<server>:<path>`) | - |
| `MOUNT_DIR` | No | Local mount point directory | `~/cluster-credentials` |

### CLI Flags

| Flag | Description |
|------|-------------|
| `--login` | Export `KUBECONFIG` to login to the cluster (allows kubectl access) |
| `--cleanup` | Unset all exported variables and unmount NFS |
| `--forklift` | Install Forklift operator (assumes already logged in via kubectl) |
| `--forklift-cleanup` | Remove Forklift operator (assumes already logged in via kubectl) |
| `--forklift-images` | List ForkliftController FQIN images |
| `--forklift-images-set <image>` | Set a specific FQIN image (auto-detects field from image name) |
| `--forklift-images-clear` | Clear all FQIN images from ForkliftController |
| `--help`, `-h` | Show help message |

## Usage

### Using the Shell Function

After shell setup, use the `kube-setup` function:

```bash
# Setup credentials for a cluster
CLUSTER=<cluster-name> kube-setup

# Login to cluster (sets KUBECONFIG)
CLUSTER=<cluster-name> kube-setup --login

# Install Forklift operator (assumes already logged in)
kube-setup --forklift

# Remove Forklift operator (assumes already logged in)
kube-setup --forklift-cleanup

# List ForkliftController FQIN images
kube-setup --forklift-images

# Set a specific FQIN image
kube-setup --forklift-images-set quay.io/kubev2v/forklift-controller:latest

# Clear all FQIN images
kube-setup --forklift-images-clear

# Cleanup
kube-setup --cleanup
```

### Direct Sourcing

If not using the shell function:

```bash
export NFS_SERVER=<nfs-server>:<path>
export CLUSTER=<cluster-name>
source ./kube-setup.sh
```

## Exported Variables

After sourcing the script, the following environment variables are available:

| Variable | Description | Condition |
|----------|-------------|-----------|
| `KUBE_USER` | Username (`kubeadmin`) | Always |
| `KUBE_PASSWORD` | Admin password | Always |
| `KUBE_API_URL` | Kubernetes API server URL | Always |
| `KUBE_UI_URL` | OpenShift web console URL | Always |
| `KUBE_TOKEN` | Bearer token for API authentication (cluster-admin) | Always |
| `KUBECONFIG` | Path to kubeconfig file | Only with `--login` |

## Token Retrieval

If the kubeconfig doesn't contain a token, the script automatically retrieves one using:

```bash
kubectl create token default -n openshift-cluster-version
```

This service account has cluster-admin privileges on OpenShift clusters.

## Examples

### Using with curl

```bash
CLUSTER=<cluster-name> kube-setup

# Make API calls using token
curl -k -H "Authorization: Bearer $KUBE_TOKEN" "$KUBE_API_URL/api/v1/namespaces"
```

### Using with kubectl

```bash
CLUSTER=<cluster-name> kube-setup --login

# kubectl now uses the cluster
kubectl get nodes
```

---

## License

MIT
