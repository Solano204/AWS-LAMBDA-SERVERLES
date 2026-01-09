#!/bin/bash
set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 CloudMart Infrastructure Deployment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check prerequisites
echo "🔍 Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed!"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed!"
    exit 1
fi

if [ ! -f "main.tf" ]; then
    echo "❌ main.tf not found!"
    exit 1
fi

if [ ! -f "terraform.tfvars" ]; then
    echo "❌ terraform.tfvars not found!"
    exit 1
fi

echo "✅ All prerequisites met"
echo ""

# Check/Create key pair
if [ ! -f "cloudmart-key.pem" ]; then
    echo "🔑 Creating EC2 key pair..."
    aws ec2 create-key-pair --key-name cloudmart-key --query 'KeyMaterial' --output text > cloudmart-key.pem 2>/dev/null || {
        echo "⚠️  Key pair already exists in AWS. Downloading is not possible."
        echo "   If you don't have the .pem file, delete the key in AWS Console and run again."
        exit 1
    }
    chmod 400 cloudmart-key.pem
    echo "✅ Key pair created: cloudmart-key.pem"
else
    echo "✅ Key pair already exists: cloudmart-key.pem"
fi
echo ""

# Initialize Terraform
echo "📦 Initializing Terraform..."
terraform init
if [ $? -ne 0 ]; then
    echo "❌ Terraform init failed!"
    exit 1
fi
echo ""

# Validate configuration
echo "🔍 Validating Terraform configuration..."
terraform validate
if [ $? -ne 0 ]; then
    echo "❌ Validation failed!"
    exit 1
fi
echo "✅ Configuration is valid"
echo ""

# Create plan
echo "📋 Creating deployment plan..."
terraform plan -out=tfplan
if [ $? -ne 0 ]; then
    echo "❌ Planning failed!"
    exit 1
fi
echo ""

# Show summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 DEPLOYMENT SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Region: us-east-1"
echo "Project: cloudmart"
echo "Email: carlosjosuelopezsolano98@gmail.com"
echo "Your IP: 177.231.65.221/32"
echo ""
echo "Resources to be created:"
echo "  • VPC with 2 subnets"
echo "  • RDS MySQL database (⏱️  takes ~5-7 minutes)"
echo "  • EC2 t2.micro instance"
echo "  • S3 bucket for images"
echo "  • DynamoDB table for cart"
echo "  • SQS queue for orders"
echo "  • SNS topic for notifications"
echo "  • Lambda function + API Gateway"
echo "  • IAM roles and security groups"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
read -p "Continue with deployment? (yes/no): " response

if [ "$response" != "yes" ]; then
    echo "❌ Deployment cancelled"
    rm -f tfplan
    exit 0
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Starting deployment..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⏱️  This will take approximately 5-7 minutes"
echo "☕ Time to grab a coffee!"
echo ""

if terraform apply tfplan; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ DEPLOYMENT SUCCESSFUL!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📧 IMPORTANT: Check your email and confirm SNS subscription!"
    echo "   Email: carlosjosuelopezsolano98@gmail.com"
    echo ""
    echo "📄 Saving outputs to outputs.txt..."
    terraform output > outputs.txt
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎯 NEXT STEPS:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1️⃣  View your infrastructure details:"
    echo "   terraform output"
    echo ""
    echo "2️⃣  Update your application.yml with the endpoints"
    echo ""
    echo "3️⃣  Build and deploy your application:"
    echo "   mvn clean package"
    echo "   (Then use the deployment_command from outputs)"
    echo ""
    echo "4️⃣  Access your application:"
    echo "   http://\$(terraform output -raw ec2_public_ip):8080"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    rm -f tfplan
    exit 0
else
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "❌ DEPLOYMENT FAILED!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Some resources may have been created."
    echo ""
    read -p "Do you want to ROLLBACK (destroy all resources)? (yes/no): " rollback
    
    if [ "$rollback" == "yes" ]; then
        echo ""
        echo "🔄 Rolling back (destroying all resources)..."
        terraform destroy -auto-approve
        if [ $? -eq 0 ]; then
            echo "✅ Rollback complete - all resources destroyed"
        else
            echo "⚠️  Rollback had errors. Run 'terraform destroy' manually."
        fi
    else
        echo ""
        echo "⚠️  Resources left in partial state."
        echo "   To clean up manually, run: terraform destroy"
    fi
    
    rm -f tfplan
    exit 1
fi
