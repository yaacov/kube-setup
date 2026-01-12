# Kube Setup Scripts

A collection of cross-platform shell scripts for Kubernetes/OpenShift cluster management.

## Scripts

- **`kube-setup.sh`** - Mount NFS-shared OpenShift cluster credentials and export them as environment variables
- **`forklift-install.sh`** - Install the Forklift operator on a Kubernetes cluster

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

# forklift-install.sh

A script to install the [Forklift](https://github.com/kubev2v/forklift) operator on a Kubernetes cluster.

## Overview

This script:

1. Installs Operator Lifecycle Manager (OLM) if not present
2. Deploys the Forklift operator from the official [kubev2v/forklift](https://github.com/kubev2v/forklift) repository
3. Creates a ForkliftController instance

## Prerequisites

- `kubectl` configured with cluster access
- Cluster admin privileges

## Usage

```bash
# Auto-detect cluster type and install
./forklift-install.sh

# Force Kubernetes mode (installs OLM)
./forklift-install.sh --k8s

# Force OpenShift mode (skips OLM)
./forklift-install.sh --ocp

# Install operator only, without creating ForkliftController
./forklift-install.sh --no-controller

# Show help
./forklift-install.sh --help
```

## Cluster Type Detection

The script automatically detects whether you're running on OpenShift or vanilla Kubernetes:

- **OpenShift (OCP)**: OLM is pre-installed, so the script skips OLM installation and directly applies the CatalogSource + Subscription
- **Kubernetes (K8s)**: OLM is installed first, then the Forklift operator

Detection is done by checking for OpenShift-specific API resources (`config.openshift.io`).

## CLI Flags

| Flag | Description |
|------|-------------|
| `--k8s` | Force Kubernetes mode (install OLM) |
| `--ocp` | Force OpenShift mode (skip OLM installation) |
| `--no-controller` | Skip creating the ForkliftController instance |
| `--help`, `-h` | Show help message |

## What Gets Installed

The script applies resources from:
- **OLM** (Kubernetes only): `https://github.com/operator-framework/operator-lifecycle-manager`
- **Forklift**: `https://raw.githubusercontent.com/kubev2v/forklift/main/operator/forklift-k8s.yaml`

### Forklift Resources Created

- Namespace: `konveyor-forklift`
- CatalogSource: `konveyor-forklift`
- OperatorGroup: `migration`
- Subscription: `forklift-operator`
- ForkliftController: `forklift-controller` (unless `--no-controller` is used)

## Checking Installation Status

```bash
# Check pods
kubectl get pods -n konveyor-forklift

# Check ForkliftController status
kubectl get forkliftcontroller -n konveyor-forklift
```

---

## License

MIT
