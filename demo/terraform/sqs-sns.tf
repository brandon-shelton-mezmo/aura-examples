# SQS Queues and SNS Topics — Bella Vista order processing pipeline

# Order queue: checkout-service → order-worker
resource "aws_sqs_queue" "orders" {
  name                       = "bella-vista-order-queue"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 5

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "bella-vista-order-queue" }
}

# Notification queue: order events → notification service
resource "aws_sqs_queue" "notifications" {
  name                       = "bella-vista-notification-queue"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400

  tags = { Name = "bella-vista-notification-queue" }
}

# Dead letter queue for failed order messages
resource "aws_sqs_queue" "dlq" {
  name                      = "bella-vista-order-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = { Name = "bella-vista-order-dlq" }
}

# SNS Topic: Order completion events
# INTENTIONAL ISSUE: No subscriptions — events go nowhere
resource "aws_sns_topic" "order_events" {
  name = "bella-vista-order-events"
  tags = { Name = "bella-vista-order-events" }
}
