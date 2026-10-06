resource "aws_ecr_repository" "app" {
  name                 = var.name
  image_tag_mutability = "MUTABLE" # bootstrap-тег перезаписується; CD використовує унікальні теги = хеш коміту
  force_delete         = true      # щоб terraform destroy видаляв реєстр разом з образами

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 15 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 15
      }
      action = { type = "expire" }
    }]
  })
}

# Збирає й пушить перший образ під час `terraform apply`,
# щоб ECS-сервіс стартував з порожнього акаунта однією командою.
# Потрібні: docker, aws cli, bash на машині, де виконується apply.
resource "terraform_data" "initial_image" {
  triggers_replace = [aws_ecr_repository.app.repository_url, var.bootstrap_tag]

  provisioner "local-exec" {
    command = "bash \"${path.module}/scripts/build_push.sh\""
    environment = {
      REPO_URL = aws_ecr_repository.app.repository_url
      REGION   = var.region
      TAG      = var.bootstrap_tag
      CONTEXT  = abspath("${path.module}/..")
    }
  }
}
