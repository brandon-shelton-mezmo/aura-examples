# Lambda Functions — Order processing and image resizing

# Dummy Lambda code (inline zip)
data "archive_file" "lambda_dummy" {
  type        = "zip"
  output_path = "${path.module}/lambda_dummy.zip"

  source {
    content  = <<-PYTHON
    def handler(event, context):
        print(f"Received event: {event}")
        return {"statusCode": 200, "body": "OK"}
    PYTHON
    filename = "lambda_function.py"
  }
}

# Order Processor — triggered by SQS, reasonable sizing
resource "aws_lambda_function" "order_processor" {
  function_name = "bella-vista-order-processor"
  role          = aws_iam_role.lambda.arn
  handler       = "lambda_function.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.lambda_dummy.output_path
  source_code_hash = data.archive_file.lambda_dummy.output_base64sha256

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.orders.url
      SNS_TOPIC = aws_sns_topic.order_events.arn
    }
  }

  tags = { Name = "bella-vista-order-processor" }
}

# SQS trigger for order processor
resource "aws_lambda_event_source_mapping" "order_processor" {
  event_source_arn = aws_sqs_queue.orders.arn
  function_name    = aws_lambda_function.order_processor.arn
  batch_size       = 10
}

# INTENTIONAL ISSUE: Over-provisioned image resizer
# 3GB memory for a simple image resize — Aura will flag as MEDIUM severity
resource "aws_lambda_function" "image_resizer" {
  function_name = "bella-vista-image-resizer"
  role          = aws_iam_role.lambda.arn
  handler       = "lambda_function.handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 3008 # WAY too much for image resizing (max allowed in sandbox)

  filename         = data.archive_file.lambda_dummy.output_path
  source_code_hash = data.archive_file.lambda_dummy.output_base64sha256

  environment {
    variables = {
      BUCKET = aws_s3_bucket.assets.id
    }
  }

  tags = { Name = "bella-vista-image-resizer" }
}
