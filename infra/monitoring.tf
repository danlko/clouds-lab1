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

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name  = "${var.name}-cpu-high"
  namespace   = "AWS/ECS"
  metric_name = "CPUUtilization"
  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

locals {
  alb_dim = ["LoadBalancer", aws_lb.main.arn_suffix]
  ecs_dim = ["ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app.name]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = var.name
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title = "Requests", region = var.region, stat = "Sum", period = 60, view = "timeSeries"
          metrics = [concat(["AWS/ApplicationELB", "RequestCount"], local.alb_dim)]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title = "5xx errors", region = var.region, stat = "Sum", period = 60, view = "timeSeries"
          metrics = [
            concat(["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count"], local.alb_dim),
            concat(["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count"], local.alb_dim),
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title = "Latency (avg / p95)", region = var.region, period = 60, view = "timeSeries"
          metrics = [
            concat(["AWS/ApplicationELB", "TargetResponseTime"], local.alb_dim, [{ stat = "Average" }]),
            concat(["AWS/ApplicationELB", "TargetResponseTime"], local.alb_dim, [{ stat = "p95" }]),
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title = "CPU / Memory (%)", region = var.region, stat = "Average", period = 60, view = "timeSeries"
          metrics = [
            concat(["AWS/ECS", "CPUUtilization"], local.ecs_dim),
            concat(["AWS/ECS", "MemoryUtilization"], local.ecs_dim),
          ]
        }
      },
      {
        type = "log", x = 0, y = 12, width = 24, height = 6
        properties = {
          title  = "Application logs"
          region = var.region
          query  = "SOURCE '${aws_cloudwatch_log_group.app.name}' | fields @timestamp, @message | sort @timestamp desc | limit 50"
          view   = "table"
        }
      },
    ]
  })
}
