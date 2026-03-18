output "role_arn" {
  description = "ARN of the Aura discovery agent IAM role"
  value       = aws_iam_role.aura_discovery.arn
}

output "role_name" {
  description = "Name of the Aura discovery agent IAM role"
  value       = aws_iam_role.aura_discovery.name
}
