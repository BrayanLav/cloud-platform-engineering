output "profile_id" {
  description = "ID del Fargate Profile"
  value       = aws_eks_fargate_profile.this.id
}

output "profile_arn" {
  description = "ARN del Fargate Profile"
  value       = aws_eks_fargate_profile.this.arn
}

output "role_arn" {
  description = "ARN del IAM Role de pod execution"
  value       = aws_iam_role.fargate.arn
}
