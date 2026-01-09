# ============================================
# OUTPUTS - Display important information
# ============================================

output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/users"
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.post_handler.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.post_handler.arn
}

output "lambda_current_version" {
  description = "Current Lambda version number"
  value       = aws_lambda_function.post_handler.version
}

output "lambda_prod_alias_arn" {
  description = "Production alias ARN"
  value       = aws_lambda_alias.prod.arn
}

output "lambda_staging_alias_arn" {
  description = "Staging alias ARN"
  value       = aws_lambda_alias.staging.arn
}

output "lambda_prod_version" {
  description = "Version that prod alias points to"
  value       = aws_lambda_alias.prod.function_version
}

output "lambda_staging_version" {
  description = "Version that staging alias points to"
  value       = aws_lambda_alias.staging.function_version
}