# AWS EC2 Migration Demo
# Run all commands from repo root: cd /path/to/kube-setup

# Login to ROSA cluster
CLUSTER=yzamir-01 kube-setup --login

# Install forklift
CLUSTER=yzamir-01 kube-setup --forklift

# Setup AWS EC2 infrastructure
EC2_REGION=us-east-1 demo/setup-aws-ec2.sh

# Get vms
aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`].Value|[0]]' --output table

# Find snapshots where forklift.konveyor.io/vmID tag exists
aws ec2 describe-snapshots \
  --filters "Name=tag-key,Values=forklift.konveyor.io/vmID"

# Find volumes where forklift.konveyor.io/vmID tag exists
aws ec2 describe-volumes \
  --filters "Name=tag-key,Values=forklift.konveyor.io/vmID"
  
###
# login to ROSA AWS

export AWS_ACCESS_KEY_ID=$(oc get secret aws-creds -n kube-system -o jsonpath='{.data.aws_access_key_id}' | base64 -d) && \
export AWS_SECRET_ACCESS_KEY=$(oc get secret aws-creds -n kube-system -o jsonpath='{.data.aws_secret_access_key}' | base64 -d) && \
export AWS_DEFAULT_REGION=us-east-1 && \
aws sts get-caller-identity
###

# Create demo namespace
oc new-project demo

# Create providers
oc mtv create provider host --type openshift
oc mtv create provider my-ec2 --type ec2 --ec2-region us-east-1 --username "$EC2_KEY" --password "$EC2_SECRET" --auto-target-credentials

# Check inventory
oc mtv get inventory vms my-ec2 

# Create plan
oc mtv create plan my-plan --source my-ec2 --vms rhel9-nitro,rhel9-xen
oc mtv start plan my-plan

# Monitor
oc mtv get plan my-plan --vms --watch
