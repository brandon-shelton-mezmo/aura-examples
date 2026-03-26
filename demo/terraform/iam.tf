# ECS Task Execution Role — shared by all tasks
# Allows pulling images from cross-account ECR and writing CloudWatch Logs
resource "aws_iam_role" "ecs_execution" {
  name = "bella-vista-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_execution" {
  name = "ecs-execution"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRCrossAccountPull"
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid    = "S3ConfigRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.configs.arn}/*"
      }
    ]
  })
}

# MCP Server Task Role — AWS API access for infrastructure discovery
resource "aws_iam_role" "mcp_task" {
  name = "bella-vista-mcp-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "mcp_task" {
  name = "mcp-discovery"
  role = aws_iam_role.mcp_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadOnlyDiscovery"
      Effect = "Allow"
      Action = [
        "ec2:Describe*",
        "ecs:Describe*", "ecs:List*",
        "rds:Describe*",
        "s3:List*", "s3:GetBucket*",
        "lambda:List*", "lambda:GetFunction*",
        "sqs:List*", "sqs:GetQueueAttributes",
        "sns:List*", "sns:GetTopicAttributes",
        "dynamodb:Describe*", "dynamodb:List*",
        "iam:List*", "iam:GetRole*", "iam:GetPolicy*",
        "cloudwatch:Describe*", "cloudwatch:List*", "cloudwatch:GetMetricData",
        "cloudtrail:LookupEvents", "cloudtrail:GetTrailStatus",
        "cloudformation:Describe*", "cloudformation:List*",
        "elasticloadbalancing:Describe*",
        "route53:List*", "route53:GetHostedZone",
        "sts:GetCallerIdentity",
        "servicequotas:List*", "servicequotas:Get*",
        "ecr:Describe*", "ecr:List*",
        "efs:Describe*",
        "secretsmanager:ListSecrets", "secretsmanager:DescribeSecret"
      ]
      Resource = "*"
    }]
  })
}

# Aura Agent Task Role — Bedrock creds passed as direct env vars (no Secrets Manager)
resource "aws_iam_role" "aura_agent_task" {
  name = "bella-vista-aura-agent-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "aura_agent_task" {
  name = "aura-agent"
  role = aws_iam_role.aura_agent_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3ConfigRead"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.configs.arn}/*"
      },
      {
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadOnlyDiscovery"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ecs:Describe*", "ecs:List*",
          "rds:Describe*",
          "s3:List*", "s3:GetBucket*",
          "lambda:List*", "lambda:GetFunction*",
          "sqs:List*", "sqs:GetQueueAttributes",
          "sns:List*", "sns:GetTopicAttributes",
          "dynamodb:Describe*", "dynamodb:List*",
          "iam:List*", "iam:GetRole*", "iam:GetPolicy*",
          "cloudwatch:Describe*", "cloudwatch:List*", "cloudwatch:GetMetricData",
          "cloudtrail:LookupEvents", "cloudtrail:GetTrailStatus",
          "cloudformation:Describe*", "cloudformation:List*",
          "elasticloadbalancing:Describe*",
          "route53:List*", "route53:GetHostedZone",
          "sts:GetCallerIdentity",
          "servicequotas:List*", "servicequotas:Get*",
          "ecr:Describe*", "ecr:List*",
          "efs:Describe*",
          "elasticfilesystem:Describe*",
          "logs:DescribeLogGroups", "logs:GetLogEvents", "logs:FilterLogEvents",
          "secretsmanager:ListSecrets", "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
      }
    ]
  })
}

# Bella Vista Task Role
resource "aws_iam_role" "bella_vista_task" {
  name = "bella-vista-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "bella_vista_task" {
  name = "bella-vista-app"
  role = aws_iam_role.bella_vista_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AppAccess"
      Effect = "Allow"
      Action = [
        "s3:GetObject", "s3:PutObject",
        "sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage",
        "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"
      ]
      Resource = "*"
    }]
  })
}

# Lambda Execution Role
resource "aws_iam_role" "lambda" {
  name = "bella-vista-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_app" {
  name = "lambda-app"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes",
        "s3:GetObject", "s3:PutObject",
        "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"
      ]
      Resource = "*"
    }]
  })
}
