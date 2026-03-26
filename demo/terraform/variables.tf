variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "ecr_account_id" {
  description = "AWS account ID that hosts the ECR images (Mezmo account)"
  type        = string
  default     = "627029844476"
}

variable "image_tag" {
  description = "Docker image tag to use for all ECR images"
  type        = string
  default     = "latest"
}

variable "bedrock_access_key_id" {
  description = "AWS access key for cross-account Bedrock LLM calls"
  type        = string
  sensitive   = true
  default     = ""
}

variable "bedrock_secret_access_key" {
  description = "AWS secret key for cross-account Bedrock LLM calls"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ecs_aura_cpu" {
  description = "CPU units for Aura agent tasks (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "ecs_aura_memory" {
  description = "Memory (MiB) for Aura agent tasks"
  type        = number
  default     = 512
}

variable "ecs_qdrant_cpu" {
  description = "CPU units for Qdrant task"
  type        = number
  default     = 512
}

variable "ecs_qdrant_memory" {
  description = "Memory (MiB) for Qdrant task"
  type        = number
  default     = 1024
}

variable "rds_instance_class" {
  description = "RDS instance class (intentionally single-AZ for demo)"
  type        = string
  default     = "db.t3.micro"
}
