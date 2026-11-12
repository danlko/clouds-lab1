# Завдання 1: горизонтальне автомасштабування ECS-сервісу за середнім CPU.
resource "aws_appautoscaling_target" "app" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.autoscaling_min
  max_capacity       = var.autoscaling_max
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-cpu-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.app.service_namespace
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_target
    scale_out_cooldown = var.scale_out_cooldown
    scale_in_cooldown  = var.scale_in_cooldown
  }
}

# Бонус 8: масштабування за розкладом (вмикається schedule_enabled = true).
# Змінює лише мінімум; target tracking працює далі в межах [min, max].
resource "aws_appautoscaling_scheduled_action" "day" {
  count              = var.schedule_enabled ? 1 : 0
  name               = "${var.name}-day"
  service_namespace  = aws_appautoscaling_target.app.service_namespace
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension
  schedule           = "cron(0 8 ? * MON-FRI *)"
  timezone           = "Europe/Kiev"

  scalable_target_action {
    min_capacity = var.schedule_day_min
    max_capacity = var.autoscaling_max
  }
}

resource "aws_appautoscaling_scheduled_action" "night" {
  count              = var.schedule_enabled ? 1 : 0
  name               = "${var.name}-night"
  service_namespace  = aws_appautoscaling_target.app.service_namespace
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension
  schedule           = "cron(0 20 ? * * *)"
  timezone           = "Europe/Kiev"

  scalable_target_action {
    min_capacity = var.schedule_night_min
    max_capacity = var.autoscaling_max
  }

  # дві дії над однією ціллю не можна створювати паралельно
  depends_on = [aws_appautoscaling_scheduled_action.day]
}
