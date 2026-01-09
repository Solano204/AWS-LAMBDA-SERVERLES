#!/bin/bash
# Script to clean up existing AWS resources before running Terraform
# WARNING: This will DELETE resources! Make sure you want to do this.

set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${RED}⚠️  WARNING: This will DELETE existing AWS resources!${NC}"
echo ""
echo "Resources to be deleted:"
echo "  - DynamoDB table: cloudmart-cart"
echo "  - S3 bucket: cloudmart-images-2024-carlos"
echo "  - SQS queue: cloudmart-order-queue"
echo "  - SNS topic: cloudmart-order-notifications"
echo "  - Lambda function: cloudmart-shipping-calculator"
echo "  - IAM role: CloudMartEC2Role"
echo "  - IAM instance profile: CloudMartEC2Profile"
echo ""
read -p "Are you SURE you want to continue? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-east-1"

echo ""
echo -e "${YELLOW}Starting cleanup...${NC}"
echo ""

# 1. Delete API Gateway (if exists)
echo "🗑️  Deleting API Gateway..."
API_ID=$(aws apigatewayv2 get-apis --query "Items[?Name=='cloudmart-shipping-api'].ApiId" --output text 2>/dev/null || echo "")
if [ ! -z "$API_ID" ]; then
    aws apigatewayv2 delete-api --api-id "$API_ID" && echo "✅ API Gateway deleted" || echo "⚠️  Failed to delete API Gateway"
else
    echo "⏭️  API Gateway not found"
fi

# 2. Delete Lambda Function
echo "🗑️  Deleting Lambda function..."
aws lambda delete-function --function-name cloudmart-shipping-calculator 2>/dev/null && echo "✅ Lambda deleted" || echo "⏭️  Lambda not found"

# 3. Delete Lambda IAM Role
echo "🗑️  Deleting Lambda IAM role..."
aws iam detach-role-policy --role-name cloudmart-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
aws iam delete-role --role-name cloudmart-lambda-role 2>/dev/null && echo "✅ Lambda role deleted" || echo "⏭️  Lambda role not found"

# 4. Delete SNS Subscriptions
echo "🗑️  Deleting SNS subscriptions..."
SNS_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:cloudmart-order-notifications"
SUBS=$(aws sns list-subscriptions-by-topic --topic-arn "$SNS_ARN" --query "Subscriptions[].SubscriptionArn" --output text 2>/dev/null || echo "")
if [ ! -z "$SUBS" ]; then
    for sub in $SUBS; do
        if [ "$sub" != "PendingConfirmation" ]; then
            aws sns unsubscribe --subscription-arn "$sub" 2>/dev/null && echo "✅ Subscription deleted: $sub" || true
        fi
    done
else
    echo "⏭️  No subscriptions found"
fi

# 5. Delete SNS Topic
echo "🗑️  Deleting SNS topic..."
aws sns delete-topic --topic-arn "$SNS_ARN" 2>/dev/null && echo "✅ SNS topic deleted" || echo "⏭️  SNS topic not found"

# 6. Purge and Delete SQS Queue
echo "🗑️  Deleting SQS queue..."
SQS_URL="https://sqs.${AWS_REGION}.amazonaws.com/${AWS_ACCOUNT_ID}/cloudmart-order-queue"
aws sqs purge-queue --queue-url "$SQS_URL" 2>/dev/null || true
sleep 2
aws sqs delete-queue --queue-url "$SQS_URL" 2>/dev/null && echo "✅ SQS queue deleted" || echo "⏭️  SQS queue not found"

# 7. Delete S3 Bucket (must be empty first)
echo "🗑️  Deleting S3 bucket..."
BUCKET_NAME="cloudmart-images-2024-carlos"
# Empty bucket first
aws s3 rm s3://$BUCKET_NAME --recursive 2>/dev/null || true
# Delete bucket
aws s3 rb s3://$BUCKET_NAME --force 2>/dev/null && echo "✅ S3 bucket deleted" || echo "⏭️  S3 bucket not found"

# 8. Delete DynamoDB Table
echo "🗑️  Deleting DynamoDB table..."
aws dynamodb delete-table --table-name cloudmart-cart 2>/dev/null && echo "✅ DynamoDB table deleted" || echo "⏭️  DynamoDB table not found"

# 9. Delete IAM Instance Profile
echo "🗑️  Deleting IAM instance profile..."
aws iam remove-role-from-instance-profile --instance-profile-name CloudMartEC2Profile --role-name CloudMartEC2Role 2>/dev/null || true
aws iam delete-instance-profile --instance-profile-name CloudMartEC2Profile 2>/dev/null && echo "✅ Instance profile deleted" || echo "⏭️  Instance profile not found"

# 10. Delete IAM Role Policies
echo "🗑️  Deleting IAM role policies..."
aws iam delete-role-policy --role-name CloudMartEC2Role --policy-name CloudMartEC2Policy 2>/dev/null || true
# Try to detach managed policies if any
ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name CloudMartEC2Role --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null || echo "")
for policy in $ATTACHED_POLICIES; do
    aws iam detach-role-policy --role-name CloudMartEC2Role --policy-arn "$policy" 2>/dev/null || true
done

# 11. Delete IAM Role
echo "🗑️  Deleting IAM role..."
aws iam delete-role --role-name CloudMartEC2Role 2>/dev/null && echo "✅ IAM role deleted" || echo "⏭️  IAM role not found"

# 12. Note about RDS - we'll let it fail and handle manually if needed
echo ""
echo -e "${YELLOW}Note: RDS database will fail due to backup retention.${NC}"
echo -e "${YELLOW}We'll fix this in the next step.${NC}"

echo ""
echo -e "${GREEN}✅ Cleanup complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Wait 60 seconds for AWS to finish processing deletions"
echo "2. Run: terraform apply"
echo "3. If RDS still fails, we'll fix the backup retention setting"