# Kind Cluster Demo for KubeVirt Migration

This demo sets up two Kind clusters to demonstrate VM migration with Forklift:
- **Source cluster**: KubeVirt + Fedora VM
- **Target cluster**: KubeVirt + Forklift

> **Note**: Run all commands from the repo root directory.

## Prerequisites

### Docker Desktop Resources

For Mac, configure in **Docker Desktop → Settings → Resources**:

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPUs     | 4       | 6+          |
| Memory   | 8GB     | 12GB+       |
| Disk     | 60GB    | 100GB+      |

> Emulation is CPU-intensive and VMs need significant RAM.

---

## Step 1: Create Kind Clusters

**Option A**: Simple (uses defaults)

```bash
kind create cluster --name source-cluster
kind create cluster --name target-cluster
```

**Option B**: With custom config (extra ports, settings)

```bash
kind create cluster --name source-cluster --config demo/kind-config.yaml
kind create cluster --name target-cluster --config demo/kind-config.yaml
```

---

## Step 2: Setup Source Cluster (KubeVirt + VM)

### Switch to source cluster

```bash
kubectl config use-context kind-source-cluster
```

### Install KubeVirt

```bash
./kubevirt-install.sh
```

### Enable emulation (required for Mac - no KVM)

```bash
kubectl patch kubevirt kubevirt -n kubevirt --type=merge \
  -p '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
kubectl delete pods -n kubevirt -l kubevirt.io=virt-handler
sleep 30
```

### Create the DataVolume

The DataVolume is created separately so it persists across VM deletions.

**For Mac (ARM)**:
```bash
kubectl apply -f demo/k8s-dv-arm64.yaml
```

**For Linux (x86)**:
```bash
kubectl apply -f demo/k8s-dv-amd64.yaml
```

### Wait for import (5-10 minutes, only needed once)

```bash
kubectl wait datavolume fedora-cloud-arm-dv --for condition=Ready --timeout=900s
```

### Create the VM

**For Mac (ARM)**:
```bash
kubectl apply -f demo/k8s-vm-arm64.yaml
```

**For Linux (x86)**:
```bash
kubectl apply -f demo/k8s-vm-amd64.yaml
```

### Wait for VM to be ready

```bash
kubectl wait vm fedora-vm-arm --for condition=Ready --timeout=120s
```

---

## Step 3: Setup Target Cluster (KubeVirt + Forklift)

### Switch to target cluster

```bash
kubectl config use-context kind-target-cluster
```

### Install KubeVirt

```bash
./kubevirt-install.sh
```

### Enable emulation

```bash
kubectl patch kubevirt kubevirt -n kubevirt --type=merge \
  -p '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
kubectl delete pods -n kubevirt -l kubevirt.io=virt-handler
sleep 30
```

### Install Forklift

```bash
./forklift-install.sh
```

### Wait for Forklift to be ready

```bash
kubectl wait deployment -n konveyor-forklift forklift-controller --for condition=Available --timeout=300s
```

---

## Step 4: Get Source Cluster Credentials

### Switch to source cluster

```bash
kubectl config use-context kind-source-cluster
```

### Get source cluster API IP

For Kind, use the internal Docker network IP:

```bash
SOURCE_API=$(docker inspect source-cluster-control-plane \
  --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
echo "Source API IP: $SOURCE_API"
```

### Create service account for Forklift

```bash
kubectl create serviceaccount forklift-migration -n default
kubectl create clusterrolebinding forklift-migration-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=default:forklift-migration
```

### Create a long-lived token

```bash
SOURCE_TOKEN=$(kubectl create token forklift-migration -n default --duration=87600h)
echo "Source Token: $SOURCE_TOKEN"
```

### Get the CA certificate

```bash
kubectl config view --raw \
  -o jsonpath='{.clusters[?(@.name=="kind-source-cluster")].cluster.certificate-authority-data}' \
  | base64 -d > /tmp/source-ca.crt
```

---

## Step 5: Create Migration (on target cluster)

### Switch to target cluster

```bash
kubectl config use-context kind-target-cluster
```

### Create namespace for migration

```bash
kubectl create namespace migration-demo
```

### Create provider and migration plan

```bash
# TODO: Add kubectl-mtv commands for creating provider and plan
```

---

## Quick Reference

### Recreate VM (without re-importing disk)

```bash
kubectl delete vm fedora-vm-arm
kubectl apply -f demo/k8s-vm-arm64.yaml
```

### Check status

```bash
kubectl get vm,vmi,datavolume,pods
```

### Cleanup clusters

```bash
kind delete cluster --name source-cluster
kind delete cluster --name target-cluster
```
