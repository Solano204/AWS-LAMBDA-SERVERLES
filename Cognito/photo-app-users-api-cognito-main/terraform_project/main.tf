terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# KMS Key for encrypting secrets
resource "aws_kms_key" "lambda_secrets" {
  description             = "KMS key for Lambda secrets encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name        = "photo-app-lambda-secrets"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "lambda_secrets" {
  name          = "alias/photo-app-lambda-secrets"
  target_key_id = aws_kms_key.lambda_secrets.key_id
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "photo-app-user-pool"

  # Password policy
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  # Auto-verified attributes
  auto_verified_attributes = ["email"]

  # User attributes
  schema {
    name                = "email"
    attribute_data_type = "String"
    mutable             = true
    required            = true

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "name"
    attribute_data_type = "String"
    mutable             = true
    required            = false

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "family_name"
    attribute_data_type = "String"
    mutable             = true
    required            = false

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "given_name"
    attribute_data_type = "String"
    mutable             = true
    required            = false

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                     = "userId"
    attribute_data_type      = "String"
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  # Username configuration
  username_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  tags = {
    Name        = "photo-app-user-pool"
    Environment = var.environment
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "photo-app-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # Token validity
  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Auth flows
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  # Prevent user existence errors
  prevent_user_existence_errors = "ENABLED"

  # Read and write attributes - MUST include all standard and custom attributes
  read_attributes = [
    "email",
    "email_verified",
    "name",
    "family_name",
    "given_name",
    "custom:userId"
  ]

  write_attributes = [
    "email",
    "name",
    "family_name",
    "given_name",
    "custom:userId"
  ]

  generate_secret = true
}

# Cognito User Groups
resource "aws_cognito_user_group" "admins" {
  name         = "Admins"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Administrator group"
}

resource "aws_cognito_user_group" "users" {
  name         = "Users"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Regular users group"
}

# Use the JAR file directly as the Lambda deployment package
locals {
  jar_file_path = "${path.module}/PhotoAppUsersAPICognito/target/PhotoAppUsersAPICognito-1.0.jar"
}

# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_exec" {
  name = "photo-app-lambda-execution-role"

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
    Name        = "photo-app-lambda-role"
    Environment = var.environment
  }
}

# Lambda Basic Execution Policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_exec.name
}

# KMS Decrypt Policy for Lambda
resource "aws_iam_role_policy" "lambda_kms" {
  name = "lambda-kms-decrypt"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.lambda_secrets.arn
      }
    ]
  })
}

# Cognito Admin Policy for AddUserToGroup function
resource "aws_iam_role_policy" "lambda_cognito" {
  name = "lambda-cognito-admin"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminAddUserToGroup",
          "cognito-idp:GetUser",
          "cognito-idp:AdminGetUser"
        ]
        Resource = aws_cognito_user_pool.main.arn
      }
    ]
  })
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "create_user" {
  name              = "/aws/lambda/photo-app-create-user"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "confirm_user" {
  name              = "/aws/lambda/photo-app-confirm-user"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "login_user" {
  name              = "/aws/lambda/photo-app-login-user"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "add_user_to_group" {
  name              = "/aws/lambda/photo-app-add-user-to-group"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "get_user" {
  name              = "/aws/lambda/photo-app-get-user"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "get_user_by_username" {
  name              = "/aws/lambda/photo-app-get-user-by-username"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "lambda_authorizer" {
  name              = "/aws/lambda/photo-app-lambda-authorizer"
  retention_in_days = 14
}

# Lambda Functions
resource "aws_lambda_function" "create_user" {
  filename         = local.jar_file_path
  function_name    = "photo-app-create-user"
  role            = aws_iam_role.lambda_exec.arn
  handler         = "com.appsdeveloperblog.aws.lambda.CreateUserHandler::handleRequest"
  source_code_hash = filebase64sha256(local.jar_file_path)
  runtime         = "java11"
  memory_size     = 512
  timeout         = 20
  architectures   = ["x86_64"]

  environment {
    variables = {
      MY_COGNITO_POOL_APP_CLIENT_ID     = aws_cognito_user_pool_client.main.id
      MY_COGNITO_POOL_APP_CLIENT_SECRET = aws_cognito_user_pool_client.main.client_secret
      MY_COGNITO_POOL_ID                = aws_cognito_user_pool.main.id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.create_user,
    aws_iam_role_policy_attachment.lambda_basic
  ]

  tags = {
    Name        = "photo-app-create-user"
    Environment = var.environment
  }
}

resource "aws_lambda_function" "confirm_user" {
  filename         = local.jar_file_path
  function_name    = "photo-app-confirm-user"
  role            = aws_iam_role.lambda_exec.arn
  handler         = "com.appsdeveloperblog.aws.lambda.ConfirmUserHandler::handleRequest"
  source_code_hash = filebase64sha256(local.jar_file_path)
  runtime         = "java11"
  memory_size     = 512
  timeout         = 20
  architectures   = ["x86_64"]

  environment {
    variables = {
      MY_COGNITO_POOL_APP_CLIENT_ID     = aws_cognito_user_pool_client.main.id
      MY_COGNITO_POOL_APP_CLIENT_SECRET = aws_cognito_user_pool_client.main.client_secret
      MY_COGNITO_POOL_ID                = aws_cognito_user_pool.main.id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.confirm_user,
    aws_iam_role_policy_attachment.lambda_basic
  ]

  tags = {
    Name        = "photo-app-confirm-user"
    Environment = var.environment
  }
}

resource "aws_lambda_function" "login_user" {
  filename         = local.jar_file_path
  function_name    = "photo-app-login-user"
  role            = aws_iam_role.lambda_exec.arn
  handler         = "com.appsdeveloperblog.aws.lambda.LoginUserHandler::handleRequest"
  source_code_hash = filebase64sha256(local.jar_file_path)
  runtime         = "java11"
  memory_size     = 512
  timeout         = 20
  architectures   = ["x86_64"]

  environment {
    variables = {
      MY_COGNITO_POOL_APP_CLIENT_ID     = aws_cognito_user_pool_client.main.id
      MY_COGNITO_POOL_APP_CLIENT_SECRET = aws_cognito_user_pool_client.main.client_secret
      MY_COGNITO_POOL_ID                = aws_cognito_user_pool.main.id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.login_user,
    aws_iam_role_policy_attachment.lambda_basic
  ]

  tags = {
    Name        = "photo-app-login-user"
    Environment = var.environment
  }
}

resource "aws_lambda_function" "add_user_to_group" {
  filename         = local.jar_file_path
  function_name    = "photo-app-add-user-to-group"
  role            = aws_iam_role.lambda_exec.arn
  handler         = "com.appsdeveloperblog.aws.lambda.AddUserToGroupHandler::handleRequest"
  source_code_hash = filebase64sha256(local.jar_file_path)
  runtime         = "java11"
  memory_size     = 512
  timeout         = 20
  architectures   = ["x86_64"]

  environment {
    variables = {
      MY_COGNITO_POOL_APP_CLIENT_ID     = aws_cognito_user_pool_client.main.id
      MY_COGNITO_POOL_APP_CLIENT_SECRET = aws_cognito_user_pool_client.main.client_secret
      MY_COGNITO_POOL_ID                = aws_cognito_user_pool.main.id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.add_user_to_group,
    aws_iam_role_policy_attachment.lambda_basic
  ]

  tags = {
    Name        = "photo-app-add-user-to-group"
    Environment = var.environment
  }
}

resource "aws_lambda_function" "get_user" {
  filename         = local.jar_file_path
  function_name    = "photo-app-get-user"
  role            = aws_iam_role.lambda_exec.arn
  handler         = "com.appsdeveloperblog.aws.lambda.GetUserHandler::handleRequest"
  source_code_hash = filebase64sha256(local.jar_file_path)
  runtime         = "java11"
  memory_size     = 512
  timeout         = 20
  architectures   = ["x86_64"]

  environment {
    variables = {
      MY_COGNITO_POOL_APP_CLIENT_ID     = aws_cognito_user_pool_client.main.id
      MY_COGNITO_POOL_APP_CLIENT_SECRET = aws_cognito_user_pool_client.main.client_secret
      MY_COGNITO_POOL_ID                = aws_cognito_user_pool.main.id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.get_user,
    aws_iam_role_policy_attachment.lambda_basic
  ]

  tags = {
    Name        = "photo-app-get-user"
    Environment = var.environment
  }
}

resource "aws_lambda_function" "get_user_by_username" {
  filename         = local.jar_file_path
  function_name    = "photo-app-get-user-by-username"
  role            = aws_iam_role.lambda_exec.arn
  handler         = "com.appsdeveloperblog.aws.lambda.GetUserByUsernameHandler::handleRequest"
  source_code_hash = filebase64sha256(local.jar_file_path)
  runtime         = "java11"
  memory_size     = 512
  timeout         = 20
  architectures   = ["x86_64"]

  environment {
    variables = {
      MY_COGNITO_POOL_APP_CLIENT_ID     = aws_cognito_user_pool_client.main.id
      MY_COGNITO_POOL_APP_CLIENT_SECRET = aws_cognito_user_pool_client.main.client_secret
      MY_COGNITO_POOL_ID                = aws_cognito_user_pool.main.id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.get_user_by_username,
    aws_iam_role_policy_attachment.lambda_basic
  ]

  tags = {
    Name        = "photo-app-get-user-by-username"
    Environment = var.environment
  }
}

resource "aws_lambda_function" "lambda_authorizer" {
  filename         = local.jar_file_path
  function_name    = "photo-app-lambda-authorizer"
  role            = aws_iam_role.lambda_exec.arn
  handler         = "com.appsdeveloperblog.aws.lambda.authorizer.LambdaAuthorizer::handleRequest"
  source_code_hash = filebase64sha256(local.jar_file_path)
  runtime         = "java11"
  memory_size     = 512
  timeout         = 20
  architectures   = ["x86_64"]

  environment {
    variables = {
      MY_COGNITO_POOL_APP_CLIENT_ID     = aws_cognito_user_pool_client.main.id
      MY_COGNITO_POOL_APP_CLIENT_SECRET = aws_cognito_user_pool_client.main.client_secret
      MY_COGNITO_POOL_ID                = aws_cognito_user_pool.main.id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_authorizer,
    aws_iam_role_policy_attachment.lambda_basic
  ]

  tags = {
    Name        = "photo-app-lambda-authorizer"
    Environment = var.environment
  }
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "photo-app-api"
  description = "Photo App Users API with Cognito"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "photo-app-api"
    Environment = var.environment
  }
}

# API Gateway Resources
resource "aws_api_gateway_resource" "users" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "users"
}

resource "aws_api_gateway_resource" "confirm" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "confirm"
}

resource "aws_api_gateway_resource" "login" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "login"
}

resource "aws_api_gateway_resource" "users_me" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.users.id
  path_part   = "me"
}

resource "aws_api_gateway_resource" "users_username" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.users.id
  path_part   = "{userName}"
}

resource "aws_api_gateway_resource" "add_to_group" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.users_username.id
  path_part   = "add-to-group"
}

# API Gateway Methods and Integrations
# POST /users - Create User
resource "aws_api_gateway_method" "create_user" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "create_user" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.users.id
  http_method             = aws_api_gateway_method.create_user.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.create_user.invoke_arn
}

# POST /confirm - Confirm User
resource "aws_api_gateway_method" "confirm_user" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.confirm.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "confirm_user" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.confirm.id
  http_method             = aws_api_gateway_method.confirm_user.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.confirm_user.invoke_arn
}

# POST /login - Login User
resource "aws_api_gateway_method" "login_user" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.login.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "login_user" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.login.id
  http_method             = aws_api_gateway_method.login_user.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.login_user.invoke_arn
}

# GET /users/me - Get User
resource "aws_api_gateway_method" "get_user" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.users_me.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_user" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.users_me.id
  http_method             = aws_api_gateway_method.get_user.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_user.invoke_arn
}

# GET /users/{userName} - Get User by Username
resource "aws_api_gateway_method" "get_user_by_username" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.users_username.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_user_by_username" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.users_username.id
  http_method             = aws_api_gateway_method.get_user_by_username.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_user_by_username.invoke_arn
}

# POST /users/{userName}/add-to-group - Add User to Group
resource "aws_api_gateway_method" "add_user_to_group" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.add_to_group.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "add_user_to_group" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.add_to_group.id
  http_method             = aws_api_gateway_method.add_user_to_group.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.add_user_to_group.invoke_arn
}

# Lambda Permissions for API Gateway
resource "aws_lambda_permission" "create_user" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_user.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "confirm_user" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.confirm_user.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "login_user" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.login_user.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "get_user" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_user.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "get_user_by_username" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_user_by_username.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "add_user_to_group" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_user_to_group.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.users.id,
      aws_api_gateway_resource.confirm.id,
      aws_api_gateway_resource.login.id,
      aws_api_gateway_method.create_user.id,
      aws_api_gateway_method.confirm_user.id,
      aws_api_gateway_method.login_user.id,
      aws_api_gateway_integration.create_user.id,
      aws_api_gateway_integration.confirm_user.id,
      aws_api_gateway_integration.login_user.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.create_user,
    aws_api_gateway_integration.confirm_user,
    aws_api_gateway_integration.login_user,
    aws_api_gateway_integration.get_user,
    aws_api_gateway_integration.get_user_by_username,
    aws_api_gateway_integration.add_user_to_group
  ]
}

# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "Prod"

  tags = {
    Name        = "photo-app-api-prod"
    Environment = var.environment
  }
}