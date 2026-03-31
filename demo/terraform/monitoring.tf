# CloudWatch Alarms — for incident response demo
# The 5xx alarm will fire when bella-vista-fail triggers errors

resource "aws_cloudwatch_metric_alarm" "checkout_5xx" {
  alarm_name          = "bella-vista-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Bella Vista checkout service returning high 5xx error rate"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.bella_vista.arn_suffix
  }

  tags = { Name = "bella-vista-5xx-high" }
}

resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "bella-vista-dlq-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Bella Vista dead letter queue has messages — orders are failing"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  tags = { Name = "bella-vista-dlq-depth" }
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "bella-vista-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Bella Vista ECS cluster CPU utilization > 80%"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = "bella-vista-web"
  }

  tags = { Name = "bella-vista-ecs-cpu-high" }
}
