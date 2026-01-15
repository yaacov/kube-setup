#!/bin/bash
# Minimal AWS EC2 Infrastructure Setup Script with idempotency

# Check if EC2_REGION is set
if [ -z "$EC2_REGION" ]; then
    echo "ERROR: EC2_REGION environment variable is not set"
    echo "Please set it first: export EC2_REGION=us-east-1"
    exit 1
fi

# Set default VM name if not provided
if [ -z "$EC2_VM_NAME" ]; then
    export EC2_VM_NAME="rhel9-instance"
    echo "EC2_VM_NAME not set, using default: $EC2_VM_NAME"
else
    echo "Using EC2_VM_NAME: $EC2_VM_NAME"
fi

echo "Setting up minimal AWS EC2 infrastructure in region: $EC2_REGION"

# 1. Create or use existing VPC
echo "Checking for existing VPC..."
export EC2_VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=default-vpc" \
    --region $EC2_REGION \
    --query 'Vpcs[0].VpcId' \
    --output text)

if [ "$EC2_VPC_ID" == "None" ] || [ -z "$EC2_VPC_ID" ]; then
    echo "Creating new VPC..."
    export EC2_VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=default-vpc}]' \
        --region $EC2_REGION \
        --query 'Vpc.VpcId' \
        --output text)
    echo "VPC Created: $EC2_VPC_ID"
else
    echo "Using existing VPC: $EC2_VPC_ID"
fi

# 2. Create or use existing Subnet
echo "Checking for existing Subnet..."
export EC2_SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=default-subnet" "Name=vpc-id,Values=$EC2_VPC_ID" \
    --region $EC2_REGION \
    --query 'Subnets[0].SubnetId' \
    --output text)

if [ "$EC2_SUBNET_ID" == "None" ] || [ -z "$EC2_SUBNET_ID" ]; then
    echo "Creating new Subnet..."
    export EC2_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id $EC2_VPC_ID \
        --cidr-block 10.0.1.0/24 \
        --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=default-subnet}]' \
        --region $EC2_REGION \
        --query 'Subnet.SubnetId' \
        --output text)
    echo "Subnet Created: $EC2_SUBNET_ID"
else
    echo "Using existing Subnet: $EC2_SUBNET_ID"
fi

# 3. Create or use existing Security Group
echo "Checking for existing Security Group..."
export EC2_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=default-sg" "Name=vpc-id,Values=$EC2_VPC_ID" \
    --region $EC2_REGION \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

if [ "$EC2_SECURITY_GROUP_ID" == "None" ] || [ -z "$EC2_SECURITY_GROUP_ID" ]; then
    echo "Creating new Security Group..."
    export EC2_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name default-sg \
        --description "Default security group" \
        --vpc-id $EC2_VPC_ID \
        --region $EC2_REGION \
        --query 'GroupId' \
        --output text)
    echo "Security Group Created: $EC2_SECURITY_GROUP_ID"
else
    echo "Using existing Security Group: $EC2_SECURITY_GROUP_ID"
fi

# 4. Get RHEL9 AMI ID
echo "Finding RHEL9 AMI..."
export EC2_AMI_ID=$(aws ec2 describe-images \
    --owners 309956199498 \
    --filters "Name=name,Values=RHEL-9*" "Name=architecture,Values=x86_64" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --region $EC2_REGION \
    --output text)
echo "RHEL9 AMI ID: $EC2_AMI_ID"

# 5. Print all environment variables
echo ""
echo "==================================="
echo "Environment Variables Set:"
echo "==================================="
echo "export EC2_REGION=$EC2_REGION"
echo "export EC2_VPC_ID=$EC2_VPC_ID"
echo "export EC2_SUBNET_ID=$EC2_SUBNET_ID"
echo "export EC2_SECURITY_GROUP_ID=$EC2_SECURITY_GROUP_ID"
echo "export EC2_AMI_ID=$EC2_AMI_ID"
echo "export EC2_VM_NAME=$EC2_VM_NAME"
echo ""
echo "==================================="
echo "Launch Instance Command:"
echo "==================================="
echo "aws ec2 run-instances \\"
echo "    --image-id \$EC2_AMI_ID \\"
echo "    --instance-type t2.micro \\"
echo "    --security-group-ids \$EC2_SECURITY_GROUP_ID \\"
echo "    --subnet-id \$EC2_SUBNET_ID \\"
echo "    --region \$EC2_REGION \\"
echo "    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value='$EC2_VM_NAME'}]'"
echo ""
echo "==================================="
echo "List Instances:"
echo "==================================="
echo "aws ec2 describe-instances \\"
echo "     --region $EC2_REGION \\"
echo "     --output json | \\"
echo "     jq '.Reservations[].Instances[] | {InstanceId, Tags}'"
echo ""

