#!/bin/bash
set -e

echo "🚀 CloudMart Infrastructure Deployment"
echo "======================================"
echo ""

# Check if key exists
if [ ! -f "cloudmart-key.pem" ]; then
    echo "🔑 Creating EC2 key pair..."
    aws ec2 create-key-pair --key-name cloudmart-key --query 'KeyMaterial' --output text > cloudmart-key.pem
    chmod 400 cloudmart-key.pem
    echo "✅ Key pair created: cloudmart-key.pem"
fi

# Get user inputs
echo ""
echo "📝 Please provide the following information:"
echo ""

read -p "Your IP address (format: x.x.x.x/32): " YOUR_IP
read -p "Database password: " -s DB_PASSWORD
echo ""
read -p "Notification email: " NOTIFICATION_EMAIL

echo ""
echo "🔍 Validating configuration..."
terraform init
terraform validate

if [ $? -ne 0 ]; then
    echo "❌ Validation failed!"
    exit 1
fi

echo ""
echo "📋 Creating deployment plan..."
terraform plan \
    -var="your_ip=$YOUR_IP" \
    -var="db_password=$DB_PASSWORD" \
    -var="notification_email=$NOTIFICATION_EMAIL" \
    -out=tfplan

if [ $? -ne 0 ]; then
    echo "❌ Planning failed!"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  REVIEW THE PLAN ABOVE CAREFULLY!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
read -p "Apply this plan? (yes/no): " response

if [ "$response" != "yes" ]; then
    echo "❌ Deployment cancelled"
    rm -f tfplan
    exit 0
fi

echo ""
echo "🚀 Deploying infrastructure..."
echo "⏱️  This will take about 5-7 minutes (RDS takes time)..."
echo ""

if terraform apply tfplan; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ DEPLOYMENT SUCCESSFUL!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📧 IMPORTANT: Check your email ($NOTIFICATION_EMAIL) and confirm the SNS subscription!"
    echo ""
    echo "📄 Your outputs have been saved. Run 'terraform output' to see them again."
    echo ""
    rm -f tfplan
    exit 0
else
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "❌ DEPLOYMENT FAILED!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    read -p "Do you want to ROLLBACK (destroy all created resources)? (yes/no): " rollback

    if [ "$rollback" == "yes" ]; then
        echo ""
        echo "🔄 Rolling back..."
        terraform destroy \
            -var="your_ip=$YOUR_IP" \
            -var="db_password=$DB_PASSWORD" \
            -var="notification_email=$NOTIFICATION_EMAIL" \
            -auto-approve
        echo "✅ Rollback complete - all resources destroyed"
    else
        echo "⚠️  Resources left in partial state. Run 'terraform destroy' manually to clean up."
    fi

    rm -f tfplan
    exit 1
fi
