# AWS EC2 Migration Demo

This demo migrates EC2 instances to OpenShift Virtualization using Forklift on a ROSA cluster.

> **Note**: Run all commands from the repo root directory.

---

## Step 1: Login to ROSA Cluster

```bash
CLUSTER=yzamir-01 kube-setup --login
```

---

## Step 2: Install Forklift

```bash
CLUSTER=yzamir-01 kube-setup --forklift
```

---

## Step 3: Setup AWS EC2 Infrastructure

```bash
EC2_REGION=us-east-1 demo/setup-aws-ec2.sh
```

### List EC2 instances

```bash
aws ec2 describe-instances \
  --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

---

## Step 4: Get AWS Credentials from ROSA

```bash
export AWS_ACCESS_KEY_ID=$(oc get secret aws-creds -n kube-system -o jsonpath='{.data.aws_access_key_id}' | base64 -d)
export AWS_SECRET_ACCESS_KEY=$(oc get secret aws-creds -n kube-system -o jsonpath='{.data.aws_secret_access_key}' | base64 -d)
export AWS_DEFAULT_REGION=us-east-1

# Verify credentials
aws sts get-caller-identity
```

---

## Step 5: Create Migration

### Create demo namespace

```bash
oc new-project demo
```

### Create providers

```bash
oc mtv create provider host --type openshift
oc mtv create provider my-ec2 --type ec2 \
  --ec2-region us-east-1 \
  --username "$EC2_KEY" \
  --password "$EC2_SECRET" \
  --auto-target-credentials
```

### Check inventory

```bash
oc mtv get inventory vms my-ec2
```

### Create and start migration plan

```bash
oc mtv create plan my-plan --source my-ec2 --vms rhel9-nitro,rhel9-xen
oc mtv start plan my-plan
```

### Monitor migration

```bash
oc mtv get plan my-plan --vms --watch
```

---

## Troubleshooting

### Find Forklift-tagged snapshots

```bash
aws ec2 describe-snapshots \
  --filters "Name=tag-key,Values=forklift.konveyor.io/vmID"
```

### Find Forklift-tagged volumes

```bash
aws ec2 describe-volumes \
  --filters "Name=tag-key,Values=forklift.konveyor.io/vmID"
```
