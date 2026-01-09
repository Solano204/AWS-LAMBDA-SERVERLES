# ============================================
# API GATEWAY MODELS
# Define the structure of JSON request and response
# ============================================

# ============================================
# REQUEST MODEL (What client sends)
# Example: {"clientName": "John", "clientEmail": "john@example.com", "clientPassword": "pass123"}
# ============================================
resource "aws_api_gateway_model" "request_user" {
  rest_api_id  = aws_api_gateway_rest_api.main.id
  name         = "modelRequestUser"
  description  = "Client Request Model - External field names"
  content_type = "application/json"

  # JSON Schema - Validates incoming data structure
  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "Client Request Model"
    type      = "object"
    properties = {
      clientName = {
        type = "string"  # Must be a string
      }
      clientEmail = {
        type = "string"
      }
      clientPassword = {
        type = "string"
      }
    }
    required = ["clientName", "clientEmail", "clientPassword"]  # These fields are mandatory
  })
}

# ============================================
# RESPONSE MODEL (What client receives)
# Example: {"status": "created", "userId": "uuid-123", "apellido": "Solano"}
# ============================================
resource "aws_api_gateway_model" "response_user" {
  rest_api_id  = aws_api_gateway_rest_api.main.id
  name         = "ModelResponseUser"
  description  = "Create User Model - Response structure"
  content_type = "application/json"

  # JSON Schema - Defines response structure
  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "Create User Model"
    type      = "object"
    properties = {
      status = {
        type = "string"
      }
      userId = {
        type = "string"
      }
      apellido = {
        type = "string"
      }
    }
  })
}