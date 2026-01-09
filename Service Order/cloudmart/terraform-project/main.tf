terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

}

provider "aws" {
  region = var.aws_region
}

# ============================================================================
# VARIABLES - Customize these
# ============================================================================

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "cloudmart"
}

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
  # Set via: terraform apply -var="db_password=YourSecurePassword123!"
}

variable "your_ip" {
  description = "Your IP for SSH access (format: x.x.x.x/32)"
  type        = string
  # Set via: terraform apply -var="your_ip=177.231.65.221/32"
}

variable "s3_bucket_suffix" {
  description = "Unique suffix for S3 bucket name"
  type        = string
  default     = "2024-carlos"
}

variable "notification_email" {
  description = "Email for SNS notifications"
  type        = string
  # Set via: terraform apply -var="notification_email=your-email@gmail.com"
}

variable "ec2_key_name" {
  description = "Name of existing EC2 key pair (create manually first)"
  type        = string
  default     = "cloudmart-key"
}

variable "frontend_url" {
  description = "Frontend URL for CORS (will be updated after EC2 creation)"
  type        = string
  default     = "http://localhost:3000"
}

# ============================================================================
# PHASE 1: NETWORKING - VPC with proper DNS settings (FIX: DNS hostnames enabled)
# ============================================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true  # FIX: Required for RDS public endpoint
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Public Subnet in AZ 1a
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-a"
  }
}

# Second Public Subnet in AZ 1b (FIX: Required for RDS subnet group)
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-b"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# ============================================================================
# PHASE 2: SECURITY GROUPS (FIX: All in same VPC, proper references)
# ============================================================================

# Backend Security Group (EC2)
resource "aws_security_group" "backend" {
  name        = "${var.project_name}-backend-sg"
  description = "Allow Web and SSH"
  vpc_id      = aws_vpc.main.id

  # SSH from your IP only (FIX: Not open to world)
  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  # Application port (Spring Boot)
  ingress {
    description = "Application port"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-backend-sg"
  }
}

# Database Security Group (FIX: References backend SG, not IP)
resource "aws_security_group" "database" {
  name        = "${var.project_name}-db-sg"
  description = "Allow EC2 to talk to DB"
  vpc_id      = aws_vpc.main.id

  # MySQL from backend security group (FIX: Security group reference, not IP)
  ingress {
    description     = "MySQL from backend"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

# ============================================================================
# PHASE 3: DATA LAYER
# ============================================================================

# RDS Subnet Group (FIX: Two subnets in different AZs)
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# RDS MySQL Instance (FIX: Proper connectivity, single SG)
resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-db"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"

  db_name  = "cloudmart"
  username = "admin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]  # FIX: Only one SG
  publicly_accessible    = true

  skip_final_snapshot = true
  apply_immediately   = true

  # FIX: Free tier doesn't support backup retention > 0
  backup_retention_period = 0  # Changed from 7 to 0 for free tier
  # backup_window not needed when retention is 0
  maintenance_window     = "mon:04:00-mon:05:00"

  tags = {
    Name = "${var.project_name}-db"
  }
}

# DynamoDB Table for Shopping Cart
resource "aws_dynamodb_table" "cart" {
  name         = "${var.project_name}-cart"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  tags = {
    Name = "${var.project_name}-cart"
  }
}

# S3 Bucket for Product Images (FIX: Proper public access)
resource "aws_s3_bucket" "images" {
  bucket = "${var.project_name}-images-${var.s3_bucket_suffix}"

  tags = {
    Name = "${var.project_name}-images"
  }
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "images" {
  bucket = aws_s3_bucket.images.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.images.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.images]
}

# ============================================================================
# PHASE 4: MESSAGING & NOTIFICATIONS (FIX: No loop, SQS not subscribed to SNS)
# ============================================================================

# SQS Queue for Orders
resource "aws_sqs_queue" "orders" {
  name                       = "${var.project_name}-order-queue"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20

  tags = {
    Name = "${var.project_name}-order-queue"
  }
}

# SNS Topic for Notifications
resource "aws_sns_topic" "orders" {
  name = "${var.project_name}-order-notifications"

  tags = {
    Name = "${var.project_name}-order-notifications"
  }
}

# Email Subscription (requires confirmation)
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.orders.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# FIX: NO SQS subscription to SNS (this was causing the infinite loop)

# ============================================================================
# PHASE 5: IAM ROLE (FIX: All required permissions including SQS ReceiveMessage)
# ============================================================================

# IAM Role for EC2
resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

# IAM Policy (FIX: Includes SQS ReceiveMessage and DeleteMessage)
resource "aws_iam_role_policy" "ec2" {
  name = "${var.project_name}-ec2-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.images.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.cart.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",  # FIX: Required for consumer
          "sqs:DeleteMessage",   # FIX: Required to remove processed messages
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.orders.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.orders.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ============================================================================
# PHASE 6: EC2 INSTANCE (FIX: Correct SG, IAM role attached)
# ============================================================================

# User Data Script
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Update system
    yum update -y

    # Install Java 17
    yum install -y java-17-amazon-corretto-headless

    # Create app directory
    mkdir -p /home/ec2-user/app
    cd /home/ec2-user/app

    # Create systemd service
    cat > /etc/systemd/system/cloudmart.service <<'SERVICEEOF'
    [Unit]
    Description=CloudMart Backend Service
    After=network.target

    [Service]
    Type=simple
    User=ec2-user
    WorkingDirectory=/home/ec2-user/app
    ExecStart=/usr/bin/java -jar /home/ec2-user/app/app.jar
    Restart=always
    RestartSec=10
    StandardOutput=append:/home/ec2-user/app/log.txt
    StandardError=append:/home/ec2-user/app/log.txt

    [Install]
    WantedBy=multi-user.target
    SERVICEEOF

    # Enable service (will start when app.jar is uploaded)
    systemctl daemon-reload
    systemctl enable cloudmart.service

    # Set ownership
    chown -R ec2-user:ec2-user /home/ec2-user/app

    echo "Setup complete. Upload app.jar to start the service."
  EOF
}

# EC2 Instance (FIX: Correct security group, IAM profile attached)
resource "aws_instance" "backend" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"
  key_name      = var.ec2_key_name

  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.backend.id]  # FIX: Correct SG
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2.name  # FIX: IAM attached

  user_data = local.user_data

  tags = {
    Name = "${var.project_name}-backend"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ============================================================================
# PHASE 7: LAMBDA & API GATEWAY
# ============================================================================

# Lambda IAM Role
resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function
resource "aws_lambda_function" "shipping" {
  filename      = "lambda_function.zip"
  function_name = "${var.project_name}-shipping-calculator"
  role          = aws_iam_role.lambda.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"

  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      DEFAULT_SHIPPING = "5.00"
      INTL_SHIPPING    = "15.00"
    }
  }
}

# Lambda source code
data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    content  = <<-EOF
      import json

      def lambda_handler(event, context):
          # Parse Input
          body = json.loads(event.get('body', '{}'))
          country = body.get('country', 'USA')

          # Logic
          shipping_cost = 5.00 if country == 'USA' else 15.00

          # Response
          return {
              'statusCode': 200,
              'headers': {
                  'Content-Type': 'application/json',
                  'Access-Control-Allow-Origin': '*'
              },
              'body': json.dumps({'shipping_cost': shipping_cost})
          }
    EOF
    filename = "lambda_function.py"
  }
}

# API Gateway
resource "aws_apigatewayv2_api" "shipping" {
  name          = "${var.project_name}-shipping-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "GET", "OPTIONS"]
    allow_headers = ["*"]
  }
}

resource "aws_apigatewayv2_integration" "shipping" {
  api_id           = aws_apigatewayv2_api.shipping.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.shipping.invoke_arn
}

resource "aws_apigatewayv2_route" "shipping" {
  api_id    = aws_apigatewayv2_api.shipping.id
  route_key = "POST /calculate"
  target    = "integrations/${aws_apigatewayv2_integration.shipping.id}"
}

resource "aws_apigatewayv2_stage" "shipping" {
  api_id      = aws_apigatewayv2_api.shipping.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.shipping.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.shipping.execution_arn}/*/*"
}

# ============================================================================
# OUTPUTS - Important values you'll need
# ============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "ec2_public_ip" {
  description = "EC2 Public IP - Use this to SSH and access your app"
  value       = aws_instance.backend.public_ip
}

output "rds_endpoint" {
  description = "RDS Endpoint - Use this in application.yml"
  value       = aws_db_instance.main.endpoint
}

output "s3_bucket_name" {
  description = "S3 Bucket Name"
  value       = aws_s3_bucket.images.id
}

output "sqs_queue_url" {
  description = "SQS Queue URL"
  value       = aws_sqs_queue.orders.url
}

output "sns_topic_arn" {
  description = "SNS Topic ARN"
  value       = aws_sns_topic.orders.arn
}

output "lambda_api_endpoint" {
  description = "Lambda API Gateway Endpoint"
  value       = aws_apigatewayv2_stage.shipping.invoke_url
}

output "application_url" {
  description = "Your application URL"
  value       = "http://${aws_instance.backend.public_ip}:8080"
}

output "deployment_command" {
  description = "Command to deploy your JAR file"
  value       = "scp -i ${var.ec2_key_name}.pem target/cloudmart-backend-0.0.1-SNAPSHOT.jar ec2-user@${aws_instance.backend.public_ip}:/home/ec2-user/app/app.jar && ssh -i ${var.ec2_key_name}.pem ec2-user@${aws_instance.backend.public_ip} 'sudo systemctl start cloudmart'"
}

output "ssh_command" {
  description = "Command to SSH into EC2"
  value       = "ssh -i ${var.ec2_key_name}.pem ec2-user@${aws_instance.backend.public_ip}"
}

output "next_steps" {
  description = "What to do next"
  value       = <<-EOT
    🎉 Infrastructure Created Successfully!

    Next Steps:
    1. Confirm your SNS email subscription (check your inbox)
    2. Update application.yml with these values:
       - RDS Endpoint: ${aws_db_instance.main.endpoint}
       - S3 Bucket: ${aws_s3_bucket.images.id}
       - SQS URL: ${aws_sqs_queue.orders.url}
       - SNS ARN: ${aws_sns_topic.orders.arn}
    3. Build your JAR: mvn clean package
    4. Deploy: ${replace(replace("scp -i ${var.ec2_key_name}.pem target/cloudmart-backend-0.0.1-SNAPSHOT.jar ec2-user@${aws_instance.backend.public_ip}:/home/ec2-user/app/app.jar", " ", "\n       "), "\n", "\n       ")}
    5. Start service: ssh and run 'sudo systemctl start cloudmart'
    6. Access your app: http://${aws_instance.backend.public_ip}:8080
  EOT
}