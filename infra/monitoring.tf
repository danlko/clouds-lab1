resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.name}-5xx"
  alarm_description   = "Застосунок повертає 5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = aws_lb.main.arn_suffix }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name  = "${var.name}-unhealthy-hosts"
  namespace   = "AWS/ApplicationELB"
  metric_name = "UnHealthyHostCount"
  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# Завдання 4: лист при CPU > 70% протягом 2 хв (ALARM) і другий лист при поверненні до норми (OK).
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name        = "${var.name}-cpu-high"
  alarm_description = "Середнє CPU сервісу ${var.name} > ${var.cpu_alarm_threshold}% протягом 2 хв. Перевірити панель: чи додаються екземпляри і чи не досягнуто максимуму (${var.autoscaling_max})."
  namespace         = "AWS/ECS"
  metric_name       = "CPUUtilization"
  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.cpu_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

locals {
  alb_dim = ["LoadBalancer", aws_lb.main.arn_suffix]
  ecs_dim = ["ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app.name]
  rds_dim = ["DBInstanceIdentifier", aws_db_instance.main.identifier]
}

# Завдання 3: панель моніторингу. Усі графіки з періодом 60 с.
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = var.name
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title = "1. Кількість екземплярів (бажана / фактична)", region = var.region
          stat  = "Average", period = 60, view = "timeSeries"
          metrics = [
            concat(["ECS/ContainerInsights", "DesiredTaskCount"], local.ecs_dim, [{ label = "Desired" }]),
            concat(["ECS/ContainerInsights", "RunningTaskCount"], local.ecs_dim, [{ label = "Running" }]),
          ]
          yAxis = { left = { min = 0, max = var.autoscaling_max + 1, showUnits = false } }
          annotations = {
            horizontal = [{ label = "max", value = var.autoscaling_max }]
          }
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title = "2. CPU сервісу, %", region = var.region, period = 60, view = "timeSeries"
          metrics = [
            concat(["AWS/ECS", "CPUUtilization"], local.ecs_dim, [{ stat = "Average", label = "CPU avg (метрика масштабування)" }]),
            concat(["AWS/ECS", "CPUUtilization"], local.ecs_dim, [{ stat = "Maximum", label = "CPU max" }]),
          ]
          yAxis = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [
              { label = "ціль масштабування ${var.cpu_target}%", value = var.cpu_target },
              { label = "поріг сповіщення ${var.cpu_alarm_threshold}%", value = var.cpu_alarm_threshold, color = "#d62728" },
            ]
          }
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title   = "3. Запити за хвилину (ALB)", region = var.region, stat = "Sum", period = 60, view = "timeSeries"
          metrics = [concat(["AWS/ApplicationELB", "RequestCount"], local.alb_dim, [{ label = "Requests / min" }])]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title = "4. Латентність p95, с", region = var.region, period = 60, view = "timeSeries"
          metrics = [
            concat(["AWS/ApplicationELB", "TargetResponseTime"], local.alb_dim, [{ stat = "p95", label = "p95" }]),
            concat(["AWS/ApplicationELB", "TargetResponseTime"], local.alb_dim, [{ stat = "p50", label = "p50" }]),
          ]
          yAxis       = { left = { min = 0 } }
          annotations = { horizontal = [{ label = "500 мс", value = 0.5 }] }
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6
        properties = {
          title = "5. Відповіді 5xx за хвилину", region = var.region, stat = "Sum", period = 60, view = "timeSeries"
          metrics = [
            concat(["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count"], local.alb_dim, [{ label = "5xx від застосунку" }]),
            concat(["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count"], local.alb_dim, [{ label = "5xx від ALB (502/503/504)" }]),
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 12, y = 12, width = 12, height = 6
        properties = {
          title = "Навантаження на БД (для порівняння з кешем)", region = var.region, period = 60, view = "timeSeries"
          metrics = [
            concat(["AWS/RDS", "CPUUtilization"], local.rds_dim, [{ stat = "Average", label = "RDS CPU, %" }]),
            concat(["AWS/RDS", "DatabaseConnections"], local.rds_dim, [{ stat = "Average", label = "З'єднання", yAxis = "right" }]),
          ]
          yAxis = { left = { min = 0 }, right = { min = 0 } }
        }
      },
      {
        type = "metric", x = 0, y = 18, width = 8, height = 6
        properties = {
          title = "Черга: довжина і вік найстарішого повідомлення", region = var.region, stat = "Maximum", period = 60, view = "timeSeries"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.books.name, { label = "Видимі повідомлення" }],
            ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", aws_sqs_queue.books.name, { label = "Вік найстарішого, с", yAxis = "right" }],
          ]
          yAxis       = { left = { min = 0 }, right = { min = 0 } }
          annotations = { horizontal = [{ label = "поріг додавання обробника", value = var.queue_scale_out_threshold }] }
        }
      },
      {
        type = "metric", x = 8, y = 18, width = 8, height = 6
        properties = {
          title = "Черга: надіслано / оброблено за хвилину", region = var.region, stat = "Sum", period = 60, view = "timeSeries"
          metrics = [
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", aws_sqs_queue.books.name, { label = "Sent" }],
            ["AWS/SQS", "NumberOfMessagesDeleted", "QueueName", aws_sqs_queue.books.name, { label = "Deleted (оброблено)" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.books_dlq.name, { label = "DLQ", stat = "Maximum" }],
          ]
        }
      },
      {
        type = "metric", x = 16, y = 18, width = 8, height = 6
        properties = {
          title = "Обробники черги (бажана / фактична)", region = var.region, stat = "Average", period = 60, view = "timeSeries"
          metrics = [
            ["ECS/ContainerInsights", "DesiredTaskCount", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.worker.name, { label = "Desired" }],
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.worker.name, { label = "Running" }],
          ]
          yAxis       = { left = { min = 0, max = var.worker_max + 1, showUnits = false } }
          annotations = { horizontal = [{ label = "max", value = var.worker_max }] }
        }
      },
      {
        type = "alarm", x = 0, y = 24, width = 24, height = 2
        properties = {
          title  = "Стан сповіщень"
          alarms = [aws_cloudwatch_metric_alarm.cpu_high.arn, aws_cloudwatch_metric_alarm.alb_5xx.arn, aws_cloudwatch_metric_alarm.unhealthy_hosts.arn]
        }
      },
      {
        type = "log", x = 0, y = 26, width = 24, height = 6
        properties = {
          title  = "Application logs"
          region = var.region
          query  = "SOURCE '${aws_cloudwatch_log_group.app.name}' | fields @timestamp, @logStream, @message | sort @timestamp desc | limit 50"
          view   = "table"
        }
      },
    ]
  })
}
