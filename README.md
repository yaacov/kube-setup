# Kube Setup Scripts

A collection of cross-platform shell scripts for Kubernetes/OpenShift cluster management.

## Scripts

- **`kube-setup.sh`** - Load OpenShift cluster credentials from NFS or CI zip files and export them as environment variables
- **`forklift-install.sh`** - Install Forklift operator on a Kubernetes/OpenShift cluster
- **`forklift-cleanup.sh`** - Remove Forklift operator from a cluster
- **`forklift-images.sh`** - Manage ForkliftController FQIN (container) images

---

# kube-setup.sh

A cross-platform shell script to load OpenShift cluster credentials from NFS shares or CI zip files and export them as environment variables.

## Overview

This script supports two modes for accessing cluster credentials:

1. **NFS Mount Mode**: Mounts an NFS share containing cluster credentials
2. **CI Zip File Mode**: Extracts credentials from a CI zip archive

Both modes export environment variables for cluster authentication and optionally set `KUBECONFIG` for kubectl access.

## Prerequisites

- **For NFS mode**:
  - NFS client installed on your system
    - **Linux**: `nfs-utils` or `nfs-common` package
    - **macOS**: Built-in NFS support
  - `sudo` access for mounting NFS shares
  - Access to the NFS server containing cluster credentials
- **For CI zip mode**:
  - `unzip` command available
  - A CI zip file with the expected structure (see below)
- `kubectl` version **1.24+** (required for automatic token retrieval)

## Installation

### Shell Setup

Add the following to your `~/.bashrc` or `~/.zshrc`:

```bash
# Kube setup configuration (choose one mode)
# Option 1: NFS mode
export NFS_SERVER="<nfs-server>:<path>"
export MOUNT_DIR="$HOME/cluster-credentials"  # optional

# Option 2: CI zip file mode
# export CI_ZIP_FILE="/path/to/credentials.zip"
# export CI_EXTRACT_DIR="$HOME/ci-credentials"  # optional

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
| `NFS_SERVER` | Yes* | NFS server address (`<server>:<path>`) | - |
| `CI_ZIP_FILE` | Yes* | Path to CI zip file containing credentials | - |
| `MOUNT_DIR` | No | NFS mount point directory | `~/cluster-credentials` |
| `CI_EXTRACT_DIR` | No | CI zip extraction directory | `~/ci-credentials` |

\* Either `NFS_SERVER` or `CI_ZIP_FILE` must be set (not both required).

### CI Zip File Structure

When using `CI_ZIP_FILE`, the zip archive must contain the following structure:

```
home/jenkins/cnv-qe.rhood.us/<CLUSTER>/auth/
├── kubeconfig
└── kubeadmin-password
```

The script will extract the zip file to `$CI_EXTRACT_DIR` (default: `~/ci-credentials`) and read credentials from there.

### CLI Flags

| Flag | Description |
|------|-------------|
| `--login` | Export `KUBECONFIG` to login to the cluster (allows kubectl access) |
| `--cleanup` | Unset all exported variables and unmount NFS / remove extracted files |
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
# NFS mode
export NFS_SERVER=<nfs-server>:<path>
export CLUSTER=<cluster-name>
source ./kube-setup.sh

# CI zip file mode
export CI_ZIP_FILE=/path/to/credentials.zip
export CLUSTER=<cluster-name>
source ./kube-setup.sh
```

### CI Zip File Mode

To use credentials from a CI zip file instead of NFS:

```bash
# Setup with CI zip file
CI_ZIP_FILE=/path/to/ci-credentials.zip CLUSTER=<cluster-name> kube-setup --login

# Cleanup (removes extracted files)
CI_ZIP_FILE=/path/to/ci-credentials.zip kube-setup --cleanup
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
