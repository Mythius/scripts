#!/bin/bash

# AWS Account Nuke Script
# WARNING: This script will DELETE ALL RESOURCES in your AWS account
# Use with extreme caution - this action is irreversible

set -e

# Color codes for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║          AWS ACCOUNT RESOURCE DELETION SCRIPT              ║${NC}"
echo -e "${RED}║                                                            ║${NC}"
echo -e "${RED}║  WARNING: This will DELETE ALL resources in your account   ║${NC}"
echo -e "${RED}║           This action is IRREVERSIBLE                      ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}ERROR: AWS CLI is not installed${NC}"
    exit 1
fi

# Get current AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}ERROR: Unable to get AWS account ID. Please check your AWS credentials.${NC}"
    exit 1
fi

echo -e "${YELLOW}Current AWS Account ID: ${ACCOUNT_ID}${NC}"
echo ""
echo -e "${RED}Type the account ID above to confirm deletion: ${NC}"
read -r CONFIRM_ACCOUNT_ID

if [ "$CONFIRM_ACCOUNT_ID" != "$ACCOUNT_ID" ]; then
    echo -e "${RED}Account ID does not match. Aborting.${NC}"
    exit 1
fi

echo ""
echo -e "${RED}Type 'DELETE-EVERYTHING' to proceed: ${NC}"
read -r FINAL_CONFIRM

if [ "$FINAL_CONFIRM" != "DELETE-EVERYTHING" ]; then
    echo -e "${RED}Confirmation failed. Aborting.${NC}"
    exit 1
fi

echo ""

# Get all regions
ALL_REGIONS=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)

echo -e "${YELLOW}Available AWS Regions:${NC}"
echo ""
i=1
declare -a REGION_ARRAY
for region in $ALL_REGIONS; do
    REGION_ARRAY[$i]=$region
    echo "  $i) $region"
    ((i++))
done
echo "  0) ALL REGIONS"
echo ""

echo -e "${GREEN}Enter region number(s) separated by spaces (e.g., '1 3 5' or '0' for all): ${NC}"
read -r REGION_SELECTION

# Parse selection
REGIONS_TO_PROCESS=""
if [[ "$REGION_SELECTION" == "0" ]]; then
    REGIONS_TO_PROCESS="$ALL_REGIONS"
    echo -e "${YELLOW}Selected: ALL REGIONS${NC}"
else
    for num in $REGION_SELECTION; do
        if [[ $num =~ ^[0-9]+$ ]] && [ $num -gt 0 ] && [ $num -lt $i ]; then
            REGIONS_TO_PROCESS="$REGIONS_TO_PROCESS ${REGION_ARRAY[$num]}"
        fi
    done
    echo -e "${YELLOW}Selected regions: $REGIONS_TO_PROCESS${NC}"
fi

if [ -z "$REGIONS_TO_PROCESS" ]; then
    echo -e "${RED}No valid regions selected. Aborting.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Starting resource deletion...${NC}"
echo ""

# Function to delete resources in a specific region
delete_in_region() {
    local region=$1
    echo -e "${YELLOW}Processing region: ${region}${NC}"

    # EC2 Instances
    echo "  - Terminating EC2 instances..."
    INSTANCE_IDS=$(aws ec2 describe-instances --region "$region" \
        --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId' \
        --output text)
    if [ -n "$INSTANCE_IDS" ]; then
        aws ec2 terminate-instances --region "$region" --instance-ids $INSTANCE_IDS 2>/dev/null || true
    fi

    # Wait for instances to terminate
    if [ -n "$INSTANCE_IDS" ]; then
        echo "  - Waiting for instances to terminate..."
        aws ec2 wait instance-terminated --region "$region" --instance-ids $INSTANCE_IDS 2>/dev/null || true
    fi

    # RDS Instances (delete without final snapshot)
    echo "  - Deleting RDS instances..."
    RDS_INSTANCES=$(aws rds describe-db-instances --region "$region" \
        --query 'DBInstances[].DBInstanceIdentifier' --output text 2>/dev/null || true)
    for db in $RDS_INSTANCES; do
        aws rds delete-db-instance --region "$region" --db-instance-identifier "$db" \
            --skip-final-snapshot --delete-automated-backups 2>/dev/null || true
    done

    # RDS Clusters
    echo "  - Deleting RDS clusters..."
    RDS_CLUSTERS=$(aws rds describe-db-clusters --region "$region" \
        --query 'DBClusters[].DBClusterIdentifier' --output text 2>/dev/null || true)
    for cluster in $RDS_CLUSTERS; do
        aws rds delete-db-cluster --region "$region" --db-cluster-identifier "$cluster" \
            --skip-final-snapshot 2>/dev/null || true
    done

    # EBS Volumes (wait for instances to terminate first)
    echo "  - Deleting EBS volumes..."
    VOLUME_IDS=$(aws ec2 describe-volumes --region "$region" \
        --query 'Volumes[?State==`available`].VolumeId' --output text 2>/dev/null || true)
    for vol in $VOLUME_IDS; do
        aws ec2 delete-volume --region "$region" --volume-id "$vol" 2>/dev/null || true
    done

    # EBS Snapshots
    echo "  - Deleting EBS snapshots..."
    SNAPSHOT_IDS=$(aws ec2 describe-snapshots --region "$region" --owner-ids "$ACCOUNT_ID" \
        --query 'Snapshots[].SnapshotId' --output text 2>/dev/null || true)
    for snap in $SNAPSHOT_IDS; do
        aws ec2 delete-snapshot --region "$region" --snapshot-id "$snap" 2>/dev/null || true
    done

    # AMIs
    echo "  - Deregistering AMIs..."
    AMI_IDS=$(aws ec2 describe-images --region "$region" --owners "$ACCOUNT_ID" \
        --query 'Images[].ImageId' --output text 2>/dev/null || true)
    for ami in $AMI_IDS; do
        aws ec2 deregister-image --region "$region" --image-id "$ami" 2>/dev/null || true
    done

    # Elastic IPs
    echo "  - Releasing Elastic IPs..."
    ALLOCATION_IDS=$(aws ec2 describe-addresses --region "$region" \
        --query 'Addresses[].AllocationId' --output text 2>/dev/null || true)
    for alloc in $ALLOCATION_IDS; do
        aws ec2 release-address --region "$region" --allocation-id "$alloc" 2>/dev/null || true
    done

    # Load Balancers (ALB/NLB)
    echo "  - Deleting Application/Network Load Balancers..."
    LB_ARNS=$(aws elbv2 describe-load-balancers --region "$region" \
        --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null || true)
    for lb in $LB_ARNS; do
        aws elbv2 delete-load-balancer --region "$region" --load-balancer-arn "$lb" 2>/dev/null || true
    done

    # Classic Load Balancers
    echo "  - Deleting Classic Load Balancers..."
    CLB_NAMES=$(aws elb describe-load-balancers --region "$region" \
        --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text 2>/dev/null || true)
    for clb in $CLB_NAMES; do
        aws elb delete-load-balancer --region "$region" --load-balancer-name "$clb" 2>/dev/null || true
    done

    # Target Groups
    echo "  - Deleting Target Groups..."
    TG_ARNS=$(aws elbv2 describe-target-groups --region "$region" \
        --query 'TargetGroups[].TargetGroupArn' --output text 2>/dev/null || true)
    for tg in $TG_ARNS; do
        aws elbv2 delete-target-group --region "$region" --target-group-arn "$tg" 2>/dev/null || true
    done

    # Lambda Functions
    echo "  - Deleting Lambda functions..."
    FUNCTIONS=$(aws lambda list-functions --region "$region" \
        --query 'Functions[].FunctionName' --output text 2>/dev/null || true)
    for func in $FUNCTIONS; do
        aws lambda delete-function --region "$region" --function-name "$func" 2>/dev/null || true
    done

    # ECS Clusters
    echo "  - Deleting ECS clusters..."
    ECS_CLUSTERS=$(aws ecs list-clusters --region "$region" \
        --query 'clusterArns[]' --output text 2>/dev/null || true)
    for cluster in $ECS_CLUSTERS; do
        # Delete services first
        SERVICES=$(aws ecs list-services --region "$region" --cluster "$cluster" \
            --query 'serviceArns[]' --output text 2>/dev/null || true)
        for service in $SERVICES; do
            aws ecs update-service --region "$region" --cluster "$cluster" \
                --service "$service" --desired-count 0 2>/dev/null || true
            aws ecs delete-service --region "$region" --cluster "$cluster" \
                --service "$service" --force 2>/dev/null || true
        done
        aws ecs delete-cluster --region "$region" --cluster "$cluster" 2>/dev/null || true
    done

    # ECR Repositories
    echo "  - Deleting ECR repositories..."
    ECR_REPOS=$(aws ecr describe-repositories --region "$region" \
        --query 'repositories[].repositoryName' --output text 2>/dev/null || true)
    for repo in $ECR_REPOS; do
        aws ecr delete-repository --region "$region" --repository-name "$repo" --force 2>/dev/null || true
    done

    # DynamoDB Tables
    echo "  - Deleting DynamoDB tables..."
    DYNAMO_TABLES=$(aws dynamodb list-tables --region "$region" \
        --query 'TableNames[]' --output text 2>/dev/null || true)
    for table in $DYNAMO_TABLES; do
        aws dynamodb delete-table --region "$region" --table-name "$table" 2>/dev/null || true
    done

    # S3 Buckets (only in us-east-1 as they're global)
    if [ "$region" = "us-east-1" ]; then
        echo "  - Emptying and deleting S3 buckets..."
        S3_BUCKETS=$(aws s3api list-buckets --query 'Buckets[].Name' --output text 2>/dev/null || true)
        for bucket in $S3_BUCKETS; do
            # Remove all versions and delete markers
            aws s3api delete-objects --bucket "$bucket" \
                --delete "$(aws s3api list-object-versions --bucket "$bucket" \
                --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --max-items 1000)" 2>/dev/null || true
            aws s3api delete-objects --bucket "$bucket" \
                --delete "$(aws s3api list-object-versions --bucket "$bucket" \
                --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --max-items 1000)" 2>/dev/null || true
            # Empty and delete bucket
            aws s3 rb "s3://$bucket" --force 2>/dev/null || true
        done
    fi

    # CloudFormation Stacks
    echo "  - Deleting CloudFormation stacks..."
    CF_STACKS=$(aws cloudformation list-stacks --region "$region" \
        --query 'StackSummaries[?StackStatus!=`DELETE_COMPLETE`].StackName' --output text 2>/dev/null || true)
    for stack in $CF_STACKS; do
        aws cloudformation delete-stack --region "$region" --stack-name "$stack" 2>/dev/null || true
    done

    # Auto Scaling Groups
    echo "  - Deleting Auto Scaling Groups..."
    ASG_NAMES=$(aws autoscaling describe-auto-scaling-groups --region "$region" \
        --query 'AutoScalingGroups[].AutoScalingGroupName' --output text 2>/dev/null || true)
    for asg in $ASG_NAMES; do
        aws autoscaling delete-auto-scaling-group --region "$region" \
            --auto-scaling-group-name "$asg" --force-delete 2>/dev/null || true
    done

    # Launch Configurations
    echo "  - Deleting Launch Configurations..."
    LAUNCH_CONFIGS=$(aws autoscaling describe-launch-configurations --region "$region" \
        --query 'LaunchConfigurations[].LaunchConfigurationName' --output text 2>/dev/null || true)
    for lc in $LAUNCH_CONFIGS; do
        aws autoscaling delete-launch-configuration --region "$region" \
            --launch-configuration-name "$lc" 2>/dev/null || true
    done

    # NAT Gateways
    echo "  - Deleting NAT Gateways..."
    NAT_GWS=$(aws ec2 describe-nat-gateways --region "$region" \
        --filter Name=state,Values=available \
        --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null || true)
    for nat in $NAT_GWS; do
        aws ec2 delete-nat-gateway --region "$region" --nat-gateway-id "$nat" 2>/dev/null || true
    done

    # Wait a bit for NAT Gateways to delete
    if [ -n "$NAT_GWS" ]; then
        echo "  - Waiting for NAT Gateways to delete..."
        sleep 30
    fi

    # Internet Gateways
    echo "  - Detaching and deleting Internet Gateways..."
    VPCS=$(aws ec2 describe-vpcs --region "$region" \
        --query 'Vpcs[?IsDefault==`false`].VpcId' --output text 2>/dev/null || true)
    for vpc in $VPCS; do
        IGWS=$(aws ec2 describe-internet-gateways --region "$region" \
            --filters "Name=attachment.vpc-id,Values=$vpc" \
            --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null || true)
        for igw in $IGWS; do
            aws ec2 detach-internet-gateway --region "$region" --internet-gateway-id "$igw" --vpc-id "$vpc" 2>/dev/null || true
            aws ec2 delete-internet-gateway --region "$region" --internet-gateway-id "$igw" 2>/dev/null || true
        done
    done

    # Security Groups (except default)
    echo "  - Deleting Security Groups..."
    for vpc in $VPCS; do
        SG_IDS=$(aws ec2 describe-security-groups --region "$region" \
            --filters "Name=vpc-id,Values=$vpc" \
            --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || true)
        # First pass: remove all rules
        for sg in $SG_IDS; do
            aws ec2 revoke-security-group-ingress --region "$region" --group-id "$sg" \
                --ip-permissions "$(aws ec2 describe-security-groups --region "$region" --group-ids "$sg" \
                --query 'SecurityGroups[0].IpPermissions' 2>/dev/null)" 2>/dev/null || true
            aws ec2 revoke-security-group-egress --region "$region" --group-id "$sg" \
                --ip-permissions "$(aws ec2 describe-security-groups --region "$region" --group-ids "$sg" \
                --query 'SecurityGroups[0].IpPermissionsEgress' 2>/dev/null)" 2>/dev/null || true
        done
        # Second pass: delete security groups
        for sg in $SG_IDS; do
            aws ec2 delete-security-group --region "$region" --group-id "$sg" 2>/dev/null || true
        done
    done

    # Subnets
    echo "  - Deleting Subnets..."
    for vpc in $VPCS; do
        SUBNET_IDS=$(aws ec2 describe-subnets --region "$region" \
            --filters "Name=vpc-id,Values=$vpc" \
            --query 'Subnets[].SubnetId' --output text 2>/dev/null || true)
        for subnet in $SUBNET_IDS; do
            aws ec2 delete-subnet --region "$region" --subnet-id "$subnet" 2>/dev/null || true
        done
    done

    # Route Tables (except main)
    echo "  - Deleting Route Tables..."
    for vpc in $VPCS; do
        RT_IDS=$(aws ec2 describe-route-tables --region "$region" \
            --filters "Name=vpc-id,Values=$vpc" \
            --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text 2>/dev/null || true)
        for rt in $RT_IDS; do
            # Disassociate first
            ASSOC_IDS=$(aws ec2 describe-route-tables --region "$region" --route-table-ids "$rt" \
                --query 'RouteTables[0].Associations[?Main!=`true`].RouteTableAssociationId' --output text 2>/dev/null || true)
            for assoc in $ASSOC_IDS; do
                aws ec2 disassociate-route-table --region "$region" --association-id "$assoc" 2>/dev/null || true
            done
            aws ec2 delete-route-table --region "$region" --route-table-id "$rt" 2>/dev/null || true
        done
    done

    # VPCs (non-default)
    echo "  - Deleting VPCs..."
    for vpc in $VPCS; do
        aws ec2 delete-vpc --region "$region" --vpc-id "$vpc" 2>/dev/null || true
    done

    # Elastic Beanstalk Applications
    echo "  - Deleting Elastic Beanstalk applications..."
    EB_APPS=$(aws elasticbeanstalk describe-applications --region "$region" \
        --query 'Applications[].ApplicationName' --output text 2>/dev/null || true)
    for app in $EB_APPS; do
        # Delete environments first
        EB_ENVS=$(aws elasticbeanstalk describe-environments --region "$region" \
            --application-name "$app" --query 'Environments[].EnvironmentName' --output text 2>/dev/null || true)
        for env in $EB_ENVS; do
            aws elasticbeanstalk terminate-environment --region "$region" --environment-name "$env" 2>/dev/null || true
        done
        aws elasticbeanstalk delete-application --region "$region" --application-name "$app" 2>/dev/null || true
    done

    # CloudWatch Log Groups
    echo "  - Deleting CloudWatch Log Groups..."
    LOG_GROUPS=$(aws logs describe-log-groups --region "$region" \
        --query 'logGroups[].logGroupName' --output text 2>/dev/null || true)
    for lg in $LOG_GROUPS; do
        aws logs delete-log-group --region "$region" --log-group-name "$lg" 2>/dev/null || true
    done

    # SNS Topics
    echo "  - Deleting SNS Topics..."
    SNS_TOPICS=$(aws sns list-topics --region "$region" \
        --query 'Topics[].TopicArn' --output text 2>/dev/null || true)
    for topic in $SNS_TOPICS; do
        aws sns delete-topic --region "$region" --topic-arn "$topic" 2>/dev/null || true
    done

    # SQS Queues
    echo "  - Deleting SQS Queues..."
    SQS_QUEUES=$(aws sqs list-queues --region "$region" \
        --query 'QueueUrls[]' --output text 2>/dev/null || true)
    for queue in $SQS_QUEUES; do
        aws sqs delete-queue --region "$region" --queue-url "$queue" 2>/dev/null || true
    done

    # Secrets Manager Secrets
    echo "  - Deleting Secrets Manager secrets..."
    SECRETS=$(aws secretsmanager list-secrets --region "$region" \
        --query 'SecretList[].Name' --output text 2>/dev/null || true)
    for secret in $SECRETS; do
        aws secretsmanager delete-secret --region "$region" --secret-id "$secret" \
            --force-delete-without-recovery 2>/dev/null || true
    done

    echo -e "${GREEN}  Completed region: ${region}${NC}"
    echo ""
}

# Delete resources in selected regions
for region in $REGIONS_TO_PROCESS; do
    delete_in_region "$region"
done

# Global resources (IAM - in any region, typically us-east-1)
echo -e "${YELLOW}Deleting global resources...${NC}"

# IAM Users
echo "  - Deleting IAM users..."
IAM_USERS=$(aws iam list-users --query 'Users[].UserName' --output text 2>/dev/null || true)
for user in $IAM_USERS; do
    # Delete access keys
    ACCESS_KEYS=$(aws iam list-access-keys --user-name "$user" \
        --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null || true)
    for key in $ACCESS_KEYS; do
        aws iam delete-access-key --user-name "$user" --access-key-id "$key" 2>/dev/null || true
    done
    # Delete login profile
    aws iam delete-login-profile --user-name "$user" 2>/dev/null || true
    # Detach policies
    USER_POLICIES=$(aws iam list-attached-user-policies --user-name "$user" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || true)
    for policy in $USER_POLICIES; do
        aws iam detach-user-policy --user-name "$user" --policy-arn "$policy" 2>/dev/null || true
    done
    # Delete inline policies
    INLINE_POLICIES=$(aws iam list-user-policies --user-name "$user" \
        --query 'PolicyNames[]' --output text 2>/dev/null || true)
    for policy in $INLINE_POLICIES; do
        aws iam delete-user-policy --user-name "$user" --policy-name "$policy" 2>/dev/null || true
    done
    # Remove from groups
    USER_GROUPS=$(aws iam list-groups-for-user --user-name "$user" \
        --query 'Groups[].GroupName' --output text 2>/dev/null || true)
    for group in $USER_GROUPS; do
        aws iam remove-user-from-group --user-name "$user" --group-name "$group" 2>/dev/null || true
    done
    aws iam delete-user --user-name "$user" 2>/dev/null || true
done

# IAM Roles
echo "  - Deleting IAM roles..."
IAM_ROLES=$(aws iam list-roles --query 'Roles[?!starts_with(RoleName, `AWSServiceRole`)].RoleName' --output text 2>/dev/null || true)
for role in $IAM_ROLES; do
    # Detach policies
    ROLE_POLICIES=$(aws iam list-attached-role-policies --role-name "$role" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || true)
    for policy in $ROLE_POLICIES; do
        aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null || true
    done
    # Delete inline policies
    INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role" \
        --query 'PolicyNames[]' --output text 2>/dev/null || true)
    for policy in $INLINE_POLICIES; do
        aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
    done
    # Delete instance profiles
    INSTANCE_PROFILES=$(aws iam list-instance-profiles-for-role --role-name "$role" \
        --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null || true)
    for profile in $INSTANCE_PROFILES; do
        aws iam remove-role-from-instance-profile --instance-profile-name "$profile" --role-name "$role" 2>/dev/null || true
        aws iam delete-instance-profile --instance-profile-name "$profile" 2>/dev/null || true
    done
    aws iam delete-role --role-name "$role" 2>/dev/null || true
done

# IAM Groups
echo "  - Deleting IAM groups..."
IAM_GROUPS=$(aws iam list-groups --query 'Groups[].GroupName' --output text 2>/dev/null || true)
for group in $IAM_GROUPS; do
    # Detach policies
    GROUP_POLICIES=$(aws iam list-attached-group-policies --group-name "$group" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || true)
    for policy in $GROUP_POLICIES; do
        aws iam detach-group-policy --group-name "$group" --policy-arn "$policy" 2>/dev/null || true
    done
    # Delete inline policies
    INLINE_POLICIES=$(aws iam list-group-policies --group-name "$group" \
        --query 'PolicyNames[]' --output text 2>/dev/null || true)
    for policy in $INLINE_POLICIES; do
        aws iam delete-group-policy --group-name "$group" --policy-name "$policy" 2>/dev/null || true
    done
    aws iam delete-group --group-name "$group" 2>/dev/null || true
done

# IAM Policies (customer managed only)
echo "  - Deleting IAM policies..."
IAM_POLICIES=$(aws iam list-policies --scope Local \
    --query 'Policies[].Arn' --output text 2>/dev/null || true)
for policy in $IAM_POLICIES; do
    # Delete all non-default versions
    POLICY_VERSIONS=$(aws iam list-policy-versions --policy-arn "$policy" \
        --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null || true)
    for version in $POLICY_VERSIONS; do
        aws iam delete-policy-version --policy-arn "$policy" --version-id "$version" 2>/dev/null || true
    done
    aws iam delete-policy --policy-arn "$policy" 2>/dev/null || true
done

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           Resource deletion process completed!             ║${NC}"
echo -e "${GREEN}║                                                            ║${NC}"
echo -e "${GREEN}║  Note: Some resources may take time to fully delete        ║${NC}"
echo -e "${GREEN}║  Check AWS Console to verify all resources are gone        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: You should also check for:${NC}"
echo "  - Route53 hosted zones and records"
echo "  - CloudFront distributions"
echo "  - AWS Config"
echo "  - AWS Backup vaults"
echo "  - Glacier vaults"
echo "  - Any resources that failed to delete above"
echo ""
