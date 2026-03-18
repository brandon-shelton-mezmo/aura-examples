variable "role_name" {
  description = "Name of the IAM role for the Aura discovery agent"
  type        = string
  default     = "aura-discovery-role"
}

variable "enable_bedrock" {
  description = "Whether to add Bedrock InvokeModel permissions to the role"
  type        = bool
  default     = true
}

variable "trusted_service_principals" {
  description = "AWS service principals allowed to assume this role"
  type        = list(string)
  default     = ["ec2.amazonaws.com", "ecs-tasks.amazonaws.com"]
}

variable "tags" {
  description = "Tags to apply to the IAM role"
  type        = map(string)
  default     = {}
}
