# ============================================
# TERRAFORM CONFIGURATION
# ============================================
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ============================================
# AWS PROVIDER
# ============================================
provider "aws" {
  region = var.aws_region
}

# ============================================
# VPC
# ============================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ============================================
# INTERNET GATEWAY
# ============================================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ============================================
# PUBLIC SUBNETS
# ============================================
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_a_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_b_cidr
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-b"
  }
}

# ============================================
# ROUTE TABLE
# ============================================
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

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# ============================================
# SECURITY GROUP
# ============================================
resource "aws_security_group" "lambda_sg" {
  name        = "${var.project_name}-lambda-sg"
  description = "Security group for Lambda function"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-lambda-sg"
  }
}

# ============================================
# IAM ROLE FOR LAMBDA
# ============================================
resource "aws_iam_role" "lambda_role" {
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

  tags = {
    Name = "${var.project_name}-lambda-role"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# ============================================
# LAMBDA FUNCTION (Base Function)
# ============================================
resource "aws_lambda_function" "post_handler" {
  filename         = "${path.module}/lambda/DataTransformationExample/target/DataTransformationExample-1.0.jar"
  function_name    = "${var.project_name}-post-handler"
  role            = aws_iam_role.lambda_role.arn
  handler         = var.lambda_handler
  source_code_hash = filebase64sha256("${path.module}/lambda/DataTransformationExample/target/DataTransformationExample-1.0.jar")
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory

  # IMPORTANT: Publish creates a new version each time code changes
  publish = true

  environment {
    variables = {
      ENVIRONMENT = "production"
      PARAM1      = "VALUE"
    }
  }

  tags = {
    Name = "${var.project_name}-lambda"
  }
}

# ============================================
# LAMBDA VERSION (Snapshot of current code)
# This creates an immutable version of your Lambda
# ============================================
resource "aws_lambda_alias" "prod" {
  name             = "prod"
  description      = "Production environment alias"
  function_name    = aws_lambda_function.post_handler.function_name
  function_version = aws_lambda_function.post_handler.version

  # Optional: For Blue/Green deployments
  # routing_config {
  #   additional_version_weights = {
  #     "2" = 0.1  # Send 10% traffic to version 2 (for testing new version)
  #   }
  # }
}

# ============================================
# LAMBDA ALIAS for STAGING (Optional)
# You can create multiple aliases for different environments
# ============================================
resource "aws_lambda_alias" "staging" {
  name             = "staging"
  description      = "Staging environment alias"
  function_name    = aws_lambda_function.post_handler.function_name
  function_version = aws_lambda_function.post_handler.version
}

# ============================================
# CLOUDWATCH LOG GROUP FOR API GATEWAY
# ============================================
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/api-gateway/${var.project_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-api-logs"
  }
}

# ============================================
# IAM ROLE FOR API GATEWAY LOGGING
# ============================================
resource "aws_iam_role" "api_gateway_cloudwatch" {
  name = "${var.project_name}-api-gateway-cloudwatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# ============================================
# API GATEWAY REST API
# ============================================
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-api"
  description = "BrainTrust User Management API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${var.project_name}-api"
  }
}

# ============================================
# API GATEWAY RESOURCE (/users)
# ============================================
resource "aws_api_gateway_resource" "users" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "users"
}

# ============================================
# REQUEST VALIDATOR
# ============================================
resource "aws_api_gateway_request_validator" "main" {
  name                        = "${var.project_name}-request-validator"
  rest_api_id                 = aws_api_gateway_rest_api.main.id
  validate_request_body       = true
  validate_request_parameters = false
}

# ============================================
# API GATEWAY METHOD (POST /users)
# ============================================
resource "aws_api_gateway_method" "post_users" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "POST"
  authorization = "NONE"

  request_validator_id = aws_api_gateway_request_validator.main.id

  request_models = {
    "application/json" = aws_api_gateway_model.request_user.name
  }
}

# ============================================
# LAMBDA INTEGRATION - USES PROD ALIAS
# API Gateway will always call the "prod" alias
# ============================================
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.users.id
  http_method             = aws_api_gateway_method.post_users.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  # IMPORTANT: Use the alias ARN instead of function ARN
  uri                     = aws_lambda_alias.prod.invoke_arn
}

# ============================================
# METHOD RESPONSE
# ============================================
resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.post_users.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# ============================================
# LAMBDA PERMISSION FOR PROD ALIAS
# API Gateway needs permission to invoke the alias
# ============================================
resource "aws_lambda_permission" "api_gateway_prod" {
  statement_id  = "AllowAPIGatewayInvokeProd"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.post_handler.function_name
  principal     = "apigateway.amazonaws.com"
  qualifier     = aws_lambda_alias.prod.name
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# ============================================
# LAMBDA PERMISSION FOR STAGING ALIAS (Optional)
# ============================================
resource "aws_lambda_permission" "api_gateway_staging" {
  statement_id  = "AllowAPIGatewayInvokeStaging"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.post_handler.function_name
  principal     = "apigateway.amazonaws.com"
  qualifier     = aws_lambda_alias.staging.name
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# ============================================
# API GATEWAY DEPLOYMENT
# ============================================
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_method_response.response_200
  ]

  lifecycle {
    create_before_destroy = true
  }

  triggers = {
    redeployment = "${timestamp()}-${sha1(jsonencode([
      aws_api_gateway_resource.users.id,
      aws_api_gateway_method.post_users.id,
      aws_api_gateway_integration.lambda_integration.id,
      aws_lambda_alias.prod.function_version,
    ]))}"
  }
}

# ============================================
# API GATEWAY STAGE
# ============================================
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId         = "$context.requestId"
      ip                = "$context.identity.sourceIp"
      requestTime       = "$context.requestTime"
      httpMethod        = "$context.httpMethod"
      resourcePath      = "$context.resourcePath"
      status            = "$context.status"
      protocol          = "$context.protocol"
      responseLength    = "$context.responseLength"
      integrationError  = "$context.integrationErrorMessage"
    })
  }

  depends_on = [aws_api_gateway_account.main]

  tags = {
    Name = "${var.project_name}-prod-stage"
  }
}

# ============================================
# API GATEWAY METHOD SETTINGS (ENABLE LOGGING)
# ============================================
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"

  settings {
    logging_level      = "INFO"
    data_trace_enabled = true
    metrics_enabled    = true
  }

  depends_on = [aws_api_gateway_stage.prod]
}

# ============================================
# API GATEWAY ACCOUNT (FOR CLOUDWATCH)
# ============================================
resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn
}