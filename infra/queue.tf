# Бонус 6: асинхронне створення книг. POST /books/async → SQS → обробник (окремий ECS-сервіс, той самий образ).
resource "aws_sqs_queue" "books_dlq" {
  name                      = "${var.name}-books-dlq"
  message_retention_seconds = 14 * 24 * 3600
}

resource "aws_sqs_queue" "books" {
  name                       = "${var.name}-books"
  visibility_timeout_seconds = 30 # повідомлення, не видалене за 30 с, знову стає видимим (повторна доставка)
  receive_wait_time_seconds  = 20 # long polling
  message_retention_seconds  = 24 * 3600

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.books_dlq.arn
    maxReceiveCount     = 5 # після 5 невдалих обробок — у DLQ
  })
}

# Застосунок може лише відправляти
resource "aws_iam_role_policy" "task_sqs_send" {
  name = "sqs-send"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["sqs:SendMessage"], Resource = aws_sqs_queue.books.arn }]
  })
}

# Обробник може лише читати й видаляти
resource "aws_iam_role" "worker" {
  name               = "${var.name}-worker"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy" "worker_sqs" {
  name = "sqs-consume"
  role = aws_iam_role.worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"]
      Resource = aws_sqs_queue.books.arn
    }]
  })
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.name}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.worker.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "worker"
    image     = "${aws_ecr_repository.app.repository_url}:${var.bootstrap_tag}"
    essential = true
    command   = ["python", "-m", "app.worker"]

    environment = concat(local.db_env, [
      { name = "SQS_QUEUE_URL", value = aws_sqs_queue.books.url },
      { name = "WORKER_WORK_SECONDS", value = tostring(var.worker_work_seconds) },
    ])
    secrets = local.db_secrets

    # SIGTERM → обробник дообробляє поточну пачку (≤10 повідомлень) і виходить
    stopTimeout = 30

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "worker"
      }
    }
  }])
}

resource "aws_ecs_service" "worker" {
  name            = "${var.name}-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_min
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.app[*].id
    security_groups  = [aws_security_group.app.id] # той самий доступ до БД, що й у застосунку
    assign_public_ip = false
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [terraform_data.initial_image]

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

# Масштабування обробника від довжини черги (step scaling: метрика не «на екземпляр», тому не target tracking)
resource "aws_appautoscaling_target" "worker" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.worker_min
  max_capacity       = var.worker_max
}

resource "aws_appautoscaling_policy" "worker_out" {
  name               = "${var.name}-worker-out"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.worker.service_namespace
  resource_id        = aws_appautoscaling_target.worker.resource_id
  scalable_dimension = aws_appautoscaling_target.worker.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    # межі — відносно порогу алярму (100): 100–1000 → +1, понад 1000 → +2
    step_adjustment {
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 900
      scaling_adjustment          = 1
    }
    step_adjustment {
      metric_interval_lower_bound = 900
      scaling_adjustment          = 2
    }
  }
}

resource "aws_appautoscaling_policy" "worker_in" {
  name               = "${var.name}-worker-in"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.worker.service_namespace
  resource_id        = aws_appautoscaling_target.worker.resource_id
  scalable_dimension = aws_appautoscaling_target.worker.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 120
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "queue_backlog_high" {
  alarm_name          = "${var.name}-queue-backlog-high"
  alarm_description   = "Черга росте — додати обробник"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.books.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = var.queue_scale_out_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_appautoscaling_policy.worker_out.arn]
}

resource "aws_cloudwatch_metric_alarm" "queue_backlog_low" {
  alarm_name          = "${var.name}-queue-backlog-low"
  alarm_description   = "Черга майже порожня — прибрати обробник"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.books.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 10
  comparison_operator = "LessThanOrEqualToThreshold"
  treat_missing_data  = "breaching" # немає даних = черга порожня
  alarm_actions       = [aws_appautoscaling_policy.worker_in.arn]
}
