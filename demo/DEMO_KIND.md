# ============================================
# Kind Cluster Demo for KubeVirt Migration
# ============================================
# Run all commands from repo root: cd /path/to/kube-setup

# ============================================
# PRE-REQUISITES: Docker Desktop Resources
# ============================================
# For Mac: Docker Desktop → Settings → Resources
#   - CPUs: 6+ (emulation is CPU-intensive)
#   - Memory: 12GB+ (VMs need RAM)
#   - Disk: 100GB+ (VM images are large)

# ============================================
# STEP 1: Create Kind Clusters
# ============================================
# Option A: Simple (uses defaults)
kind create cluster --name source-cluster
kind create cluster --name target-cluster

# Option B: With config (extra ports, settings)
# kind create cluster --name source-cluster --config demo/kind-config.yaml
# kind create cluster --name target-cluster --config demo/kind-config.yaml

# ============================================
# STEP 2: Setup Source Cluster (KubeVirt + VM)
# ============================================
kubectl config use-context kind-source-cluster

# Install KubeVirt
./kubevirt-install.sh

# Enable emulation for Mac (no KVM)
kubectl patch kubevirt kubevirt -n kubevirt --type=merge \
  -p '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
kubectl delete pods -n kubevirt -l kubevirt.io=virt-handler
sleep 30

# Create the DataVolume first (this persists across VM deletions)
# For Mac (ARM)
kubectl apply -f demo/k8s-dv-arm64.yaml
# For Linux (x86)
# kubectl apply -f demo/k8s-dv-amd64.yaml

# Wait for DataVolume to import (can take 5-10 minutes, only needed once)
echo "Waiting for disk image to import..."
kubectl wait datavolume fedora-cloud-arm-dv --for condition=Ready --timeout=900s

# Create the VM (can delete/recreate without re-importing the disk)
# For Mac (ARM)
kubectl apply -f demo/k8s-vm-arm64.yaml
# For Linux (x86)
# kubectl apply -f demo/k8s-vm-amd64.yaml

# Wait for VM to be ready
kubectl wait vm fedora-vm-arm --for condition=Ready --timeout=120s

# ============================================
# STEP 3: Setup Target Cluster (KubeVirt + Forklift)
# ============================================
kubectl config use-context kind-target-cluster

# Install KubeVirt
./kubevirt-install.sh

# Enable emulation
kubectl patch kubevirt kubevirt -n kubevirt --type=merge \
  -p '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
kubectl delete pods -n kubevirt -l kubevirt.io=virt-handler
sleep 30

# Install Forklift
./forklift-install.sh

# Wait for Forklift to be ready
echo "Waiting for Forklift..."
sleep 60
kubectl wait deployment -n konveyor-forklift forklift-controller --for condition=Available --timeout=300s

# ============================================
# STEP 4: Get Source Cluster Credentials
# ============================================
kubectl config use-context kind-source-cluster

# Get source cluster URL (for Kind, need to use internal docker network)
SOURCE_API=$(docker inspect source-cluster-control-plane --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
echo "Source API IP: $SOURCE_API"

# Create a service account with cluster-admin for Forklift
kubectl create serviceaccount forklift-migration -n default
kubectl create clusterrolebinding forklift-migration-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=default:forklift-migration

# Create a long-lived token
SOURCE_TOKEN=$(kubectl create token forklift-migration -n default --duration=87600h)
echo "Source Token: $SOURCE_TOKEN"

# Get the CA cert
kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="kind-source-cluster")].cluster.certificate-authority-data}' | base64 -d > /tmp/source-ca.crt

# ============================================
# STEP 5: Create Migration (on target cluster)
# ============================================
kubectl config use-context kind-target-cluster

# Create namespace for migration
kubectl create namespace migration-demo

# ============================================
# Quick VM Recreation (after DV is imported)
# ============================================
# If you need to recreate the VM without waiting for import:
# kubectl delete vm fedora-vm-arm
# kubectl apply -f demo/k8s-vm-arm64.yaml
