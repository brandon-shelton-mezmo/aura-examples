terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  project = "aura-sregym-demo"
  tags = {
    Project = local.project
    Owner   = var.owner_tag
  }
}

# Use the account's default VPC. Phase 1 is deliberately minimal — one
# EC2, one SG, no custom networking. Mirror Bella Vista's full VPC layout
# in phase 2 if the Instruqt port needs to match that shape.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  # us-east-1e doesn't carry m5.xlarge capacity in this account; restrict to
  # AZs that do. (`aws ec2 describe-instance-type-offerings` confirms a,b,c,d,f.)
  filter {
    name   = "availability-zone"
    values = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]
  }
}

# Amazon Linux 2023 — same family as the SREGym batch AMIs we know work.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
