resource "aws_cognito_user_pool" "main" {
  name                = var.name
  username_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }
}

resource "aws_cognito_user_pool_client" "api" {
  name         = "${var.name}-api"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  access_token_validity = 60
  token_validity_units {
    access_token = "minutes"
  }
}

resource "aws_cognito_user" "demo" {
  user_pool_id   = aws_cognito_user_pool.main.id
  username       = var.demo_user_email
  password       = var.demo_user_password
  message_action = "SUPPRESS"

  attributes = {
    email          = var.demo_user_email
    email_verified = "true"
  }
}
