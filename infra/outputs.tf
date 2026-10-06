output "app_url" {
  value = "http://${aws_lb.main.dns_name}"
}

output "swagger_url" {
  value = "http://${aws_lb.main.dns_name}/docs"
}

output "region" {
  value = var.region
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "github_actions_role_arn" {
  description = "Покласти в GitHub → Settings → Variables → AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.api.id
}

output "db_endpoint" {
  value = aws_db_instance.main.address
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
