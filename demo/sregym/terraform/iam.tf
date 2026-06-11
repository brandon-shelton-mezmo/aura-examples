# Minimal IAM for the demo instance:
#   - bedrock:InvokeModel* on the Sonnet 4.6 inference profile
#     (the bootstrap script ALSO accepts cross-account keys via env file;
#     this profile-based access is the local-region fallback)
#   - s3:GetObject on the demo S3 bucket (only relevant when var.demo_s3_bucket
#     is set — i.e. when we're pulling a pre-built aura-web-server binary)
resource "aws_iam_role" "demo" {
  name = "${local.project}-instance"
  tags = local.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "demo" {
  name = "${local.project}-policy"
  role = aws_iam_role.demo.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "BedrockInvoke"
          Effect = "Allow"
          Action = [
            "bedrock:InvokeModel",
            "bedrock:InvokeModelWithResponseStream",
          ]
          Resource = "*"
        },
      ],
      var.demo_s3_bucket == "" ? [] : [
        {
          Sid    = "DemoBucketRead"
          Effect = "Allow"
          Action = ["s3:GetObject", "s3:ListBucket"]
          Resource = [
            "arn:aws:s3:::${var.demo_s3_bucket}",
            "arn:aws:s3:::${var.demo_s3_bucket}/*",
          ]
        },
      ],
    )
  })
}

resource "aws_iam_instance_profile" "demo" {
  name = "${local.project}-instance"
  role = aws_iam_role.demo.name
  tags = local.tags
}
