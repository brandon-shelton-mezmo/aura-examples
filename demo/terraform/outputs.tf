output "alb_dns_name" {
  description = "ALB DNS name — access Bella Vista and Aura agents"
  value       = aws_lb.main.dns_name
}

output "internal_alb_dns_name" {
  description = "Internal ALB DNS — service-to-service communication"
  value       = aws_lb.internal.dns_name
}

output "account_id" {
  description = "AWS account ID of this sandbox"
  value       = local.account_id
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "s3_config_bucket" {
  description = "S3 bucket for Aura agent configs"
  value       = aws_s3_bucket.configs.id
}
