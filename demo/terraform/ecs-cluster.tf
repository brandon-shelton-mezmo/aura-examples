# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "bella-vista"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "bella-vista" }
}

# EFS Filesystem for Qdrant persistent storage
resource "aws_efs_file_system" "qdrant" {
  creation_token = "bella-vista-qdrant"
  encrypted      = true

  tags = { Name = "bella-vista-qdrant-data" }
}

resource "aws_efs_mount_target" "qdrant_a" {
  file_system_id  = aws_efs_file_system.qdrant.id
  subnet_id       = aws_subnet.private_a.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "qdrant_b" {
  file_system_id  = aws_efs_file_system.qdrant.id
  subnet_id       = aws_subnet.private_b.id
  security_groups = [aws_security_group.efs.id]
}

# S3 bucket for Aura agent TOML configs
resource "aws_s3_bucket" "configs" {
  bucket = "bella-vista-aura-configs-${local.suffix}"
  tags   = { Name = "bella-vista-aura-configs" }
}

resource "aws_s3_bucket_public_access_block" "configs" {
  bucket = aws_s3_bucket.configs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudWatch Log Group for all ECS tasks
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/bella-vista"
  retention_in_days = 7
}
