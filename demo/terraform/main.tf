terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      demo       = "aura-bella-vista"
      managed_by = "terraform"
      project    = "aura-instruqt-demo"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  suffix     = random_id.suffix.hex

  # ECR images in the Mezmo account (cross-account pull)
  ecr_registry   = "${var.ecr_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  aura_image     = "${local.ecr_registry}/aura-demo/aura:${var.image_tag}"
  qdrant_mcp_img = "${local.ecr_registry}/aura-demo/qdrant-mcp:${var.image_tag}"
  worker_mcp_img = "${local.ecr_registry}/aura-demo/worker-mcp:${var.image_tag}"
  aws_mcp_img    = "${local.ecr_registry}/aura-demo/aws-api-mcp:${var.image_tag}"
  bella_vista_img = "${local.ecr_registry}/restaurant-app:${var.image_tag}"
  qdrant_image   = "qdrant/qdrant:latest"

  # Note: Cloud Map not available in Instruqt sandboxes.
  # Using internal ALB for service-to-service communication instead.
}
