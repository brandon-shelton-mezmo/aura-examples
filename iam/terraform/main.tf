# Aura Discovery Agent — Read-Only IAM Role
# Usage: cd iam/terraform && terraform init && terraform apply

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = var.trusted_service_principals
    }
  }
}

resource "aws_iam_role" "aura_discovery" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "discovery_readonly" {
  statement {
    sid    = "ReadOnlyDiscovery"
    effect = "Allow"

    actions = [
      "sts:GetCallerIdentity",
      "ec2:Describe*",
      "ecs:Describe*",
      "ecs:List*",
      "lambda:List*",
      "lambda:GetFunction",
      "lambda:GetPolicy",
      "rds:Describe*",
      "dynamodb:Describe*",
      "dynamodb:List*",
      "s3:ListAllMyBuckets",
      "s3:GetBucketLocation",
      "s3:GetBucketPolicy",
      "s3:GetBucketTagging",
      "s3:GetEncryptionConfiguration",
      "iam:List*",
      "iam:GetRole",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "elasticloadbalancing:Describe*",
      "route53:List*",
      "route53:GetHostedZone",
      "cloudfront:List*",
      "cloudfront:GetDistribution",
      "sqs:List*",
      "sqs:GetQueueAttributes",
      "sns:List*",
      "sns:GetTopicAttributes",
      "cloudformation:Describe*",
      "cloudformation:List*",
      "cloudwatch:Describe*",
      "cloudwatch:List*",
      "logs:Describe*",
      "secretsmanager:ListSecrets",
      "secretsmanager:DescribeSecret",
      "ssm:DescribeParameters",
      "eks:Describe*",
      "eks:List*",
    ]

    resources = ["*"]
  }

  dynamic "statement" {
    for_each = var.enable_bedrock ? [1] : []

    content {
      sid    = "BedrockInvoke"
      effect = "Allow"

      actions = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
      ]

      resources = ["*"]
    }
  }
}

resource "aws_iam_role_policy" "aura_discovery" {
  name   = "${var.role_name}-policy"
  role   = aws_iam_role.aura_discovery.id
  policy = data.aws_iam_policy_document.discovery_readonly.json
}
