variable "aws_region" {
  description = "AWS region. Must have Bedrock access to us.anthropic.claude-sonnet-4-6."
  type        = string
  default     = "us-east-1"
}

variable "owner_tag" {
  description = "Value for the Owner tag (e.g. your email)."
  type        = string
}

variable "key_name" {
  description = "Name of an existing EC2 key pair in this region for SSH access."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type. m5.xlarge proven adequate for kind + social-network + AURA."
  type        = string
  default     = "m5.xlarge"
}

variable "your_ip_cidr" {
  description = "CIDR for SSH + AURA HTTP ingress (e.g. 1.2.3.4/32). Use 0.0.0.0/0 only for short-lived debug sessions."
  type        = string
}

variable "bedrock_access_key_id" {
  description = "Cross-account access key for Bedrock (Mezmo Bedrock account)."
  type        = string
  sensitive   = true
}

variable "bedrock_secret_access_key" {
  description = "Cross-account secret key for Bedrock."
  type        = string
  sensitive   = true
}

variable "aura_git_ref" {
  description = "AURA git ref to build from. Default: main."
  type        = string
  default     = "main"
}

variable "sregym_commit_sha" {
  description = "SREGym commit to pin. Default: main (replace with a SHA once we settle on a stable point)."
  type        = string
  default     = "main"
}

variable "demo_s3_bucket" {
  description = "Optional S3 bucket holding pre-built artifacts (aura-web-server binary, SREGym tarball). Empty = clone + build from source at boot."
  type        = string
  default     = ""
}
