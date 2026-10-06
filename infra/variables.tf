variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "name" {
  description = "Префікс імен усіх ресурсів. Має збігатися з APP_NAME у .github/workflows/deploy.yml"
  type        = string
  default     = "lab1-books"
}

variable "github_repo" {
  description = "Репозиторій у форматі owner/repo (для OIDC-довіри GitHub Actions)"
  type        = string
}

variable "alert_email" {
  description = "Email для алертів CloudWatch та сповіщень бюджету"
  type        = string
}

variable "demo_user_email" {
  description = "Email тестового користувача Cognito"
  type        = string
}

variable "demo_user_password" {
  description = "Пароль тестового користувача (мін. 8 символів, великі/малі літери, цифра, спецсимвол)"
  type        = string
  sensitive   = true
}

variable "budget_limit_usd" {
  type    = string
  default = "10"
}

variable "container_port" {
  type    = number
  default = 8000
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "bootstrap_tag" {
  description = "Тег початкового образу, який Terraform збирає й пушить при першому apply"
  type        = string
  default     = "bootstrap"
}
